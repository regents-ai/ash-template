defmodule AshTemplateWeb.FeedController do
  @moduledoc """
  A signed agent's live feed, `GET /api/v1/feed`: one open answer of
  server-sent events (`text/event-stream`), each a line of JSON
  (`AshTemplate.Feed`) the moment it is posted. The signature is checked once,
  as the feed opens.

  - Each event carries an `id:`, its time in microseconds. A reconnect that
    sends it back as `Last-Event-ID` first gets what it missed, up to 100;
    past that, or for an id that is not one of these, `{"kind": "resync"}`
    says to list through the ordinary routes.
  - A comment line, `: keep-alive`, every `keep_alive_ms`, so a proxy never
    closes a quiet feed.
  - One feed per agent: opening another, on any machine, closes this one with
    `{"kind": "closed", "reason": "replaced"}`. A pairing that ends or changes
    closes it with `"reason": "pairing_changed"`, so the agent reconnects as it
    now is.
  - At most `max_open` feeds on one machine; past that the open is refused.

  The feed is this request's own process waiting for messages. It holds no
  database connection while it waits: each read takes one and gives it back.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Feed
  alias RegentHttp.UnexpectedFailure

  @feeds AshTemplateWeb.OpenFeeds

  @errors %{
    "feed_full" =>
      {503, "This site has as many feeds open as it can hold right now.",
       "Try again in a minute."},
    "unavailable" => {503, "The feed could not be opened right now.", "Try again in a moment."}
  }

  @doc "The registry that counts this machine's open feeds."
  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @feeds)

  def show(conn, _params) do
    actor = conn.assigns.actor

    with :ok <- admit(actor),
         {:ok, feed} <- Feed.open(actor) do
      topics = listen(feed)

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-store")
        |> send_chunked(200)
        |> start(feed, last_event_id(conn))

      stop_listening(actor, topics)
      conn
    else
      :full ->
        refuse(conn, "feed_full")

      {:error, error} ->
        Registry.unregister(@feeds, actor.agent_id)
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # Registered first and counted after, so feeds opening together cannot all
  # read a count below the limit and pass.
  defp admit(%Agent{agent_id: id}) do
    {:ok, _owner} = Registry.register(@feeds, id, nil)

    if Registry.count(@feeds) > setting(:max_open) do
      Registry.unregister(@feeds, id)
      :full
    else
      :ok
    end
  end

  # Subscribed to its own topic first, then told, so of two feeds opening
  # together at least the older one hears the newer.
  defp listen(%Feed{actor: actor} = feed) do
    own = "agent_feed:#{actor.agent_id}"

    pairing =
      if actor.pairing == :active, do: [RegentAgents.topic(actor.privy_user_id)], else: []

    topics = [own | pairing ++ Feed.topics(feed)]
    Enum.each(topics, &Phoenix.PubSub.subscribe(AshTemplate.PubSub, &1))
    Phoenix.PubSub.broadcast_from(AshTemplate.PubSub, self(), own, :feed_replaced)
    topics
  end

  # The connection's process may go on to answer another request, so the feed
  # leaves nothing behind in it.
  defp stop_listening(actor, topics) do
    Enum.each(topics, &Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, &1))
    Registry.unregister(@feeds, actor.agent_id)
  end

  # The pairing was checked again just before the answer left
  # (`AshTemplateWeb.Plugs.AgentWallet`); a refusal there replaced it.
  defp start(%Plug.Conn{status: 200} = conn, feed, since) do
    state = %{feed: feed, seen: MapSet.new(), timer: keep_alive()}

    case catch_up(conn, state, since) do
      {:ok, conn, state} -> loop(conn, state)
      {:error, conn} -> stop_timer(conn, state)
    end
  end

  defp start(conn, _feed, _since) do
    {:ok, conn} = chunk(conn, conn.resp_body)
    conn
  end

  defp catch_up(conn, state, nil), do: {:ok, conn, state}
  defp catch_up(conn, state, :invalid), do: resync(conn, state)

  defp catch_up(conn, state, since) do
    case Feed.missed(state.feed, since) do
      {:ok, events} ->
        with {:ok, conn} <- send_events(conn, events),
             do: {:ok, conn, %{state | seen: MapSet.new(events, & &1.id)}}

      :resync ->
        resync(conn, state)

      {:error, error} ->
        UnexpectedFailure.log(conn, error)
        resync(conn, state)
    end
  end

  defp resync(conn, state) do
    with {:ok, conn} <- send_data(conn, %{kind: "resync"}), do: {:ok, conn, state}
  end

  # `seen` is what the catch-up sent, which the feed may hear again.
  defp loop(conn, state) do
    receive do
      %{topic: _, event: _, payload: _} = notice ->
        case Feed.heard(state.feed, notice) do
          {:ok, events, feed} ->
            events = Enum.reject(events, &MapSet.member?(state.seen, &1.id))
            continue(send_events(conn, events), %{state | feed: feed})

          {:error, error} ->
            UnexpectedFailure.log(conn, error)
            continue(send_data(conn, %{kind: "resync"}), state)
        end

      :keep_alive ->
        continue(write(conn, ": keep-alive\n\n"), %{state | timer: keep_alive()})

      :feed_replaced ->
        close(conn, state, "replaced")

      :agents_changed ->
        if paired_as_before?(state.feed.actor),
          do: loop(conn, state),
          else: close(conn, state, "pairing_changed")
    end
  end

  defp continue({:ok, conn}, state), do: loop(conn, state)
  defp continue({:error, conn}, state), do: stop_timer(conn, state)

  defp paired_as_before?(%Agent{wallet_address: wallet, pairing_id: id}) do
    match?({:ok, %{id: ^id}}, RegentAgents.Authority.resolve(AshTemplate.Repo, wallet))
  end

  defp close(conn, state, reason) do
    {_sent, conn} = send_data(conn, %{kind: "closed", reason: reason})
    stop_timer(conn, state)
  end

  defp stop_timer(conn, %{timer: timer}) do
    Process.cancel_timer(timer)

    receive do
      :keep_alive -> conn
    after
      0 -> conn
    end
  end

  defp send_events(conn, events) do
    Enum.reduce_while(events, {:ok, conn}, fn event, {:ok, conn} ->
      id = DateTime.to_unix(event.at, :microsecond)

      case send_frame(conn, ["id: ", Integer.to_string(id), "\n"], event) do
        {:ok, conn} -> {:cont, {:ok, conn}}
        failed -> {:halt, failed}
      end
    end)
  end

  defp send_data(conn, data), do: send_frame(conn, [], data)

  defp send_frame(conn, id_line, data),
    do: write(conn, [id_line, "data: ", Jason.encode_to_iodata!(data), "\n\n"])

  # A reader that has gone away ends the feed.
  defp write(conn, iodata) do
    case chunk(conn, iodata) do
      {:ok, conn} -> {:ok, conn}
      {:error, _closed} -> {:error, conn}
    end
  end

  defp keep_alive, do: Process.send_after(self(), :keep_alive, setting(:keep_alive_ms))

  # Nil when none was sent; :invalid for one that is not a feed's id, which
  # reads as a resync.
  defp last_event_id(conn) do
    with [id] <- get_req_header(conn, "last-event-id"),
         {microseconds, ""} <- Integer.parse(id),
         {:ok, since} <- DateTime.from_unix(microseconds, :microsecond) do
      since
    else
      [] -> nil
      _invalid -> :invalid
    end
  end

  defp setting(key),
    do: :ash_template |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
