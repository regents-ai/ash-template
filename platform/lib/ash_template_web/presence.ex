defmodule AshTemplateWeb.Presence do
  @moduledoc """
  Who has a room open. Each signed-in person's open room pages are tracked on
  `topic/1` under their account id, so several tabs count once; visitors who
  are not signed in are not listed.

  Each change is worked out once on each machine (`handle_metas/4`) into who
  arrived and who left, and that machine's pages that list the room's people
  hear it on `here_topic/1` as `{:here, room, arrived, left}`: `arrived` as
  `people/1` lists them, `left` as account ids. A page never lists the room
  again for a change.
  """

  use Phoenix.Presence, otp_app: :ash_template, pubsub_server: AshTemplate.PubSub

  @doc "The topic a room's presence is tracked on."
  def topic(room), do: "room_people:#{room}"

  @doc "The topic a room's pages hear who arrived and who left on."
  def here_topic(room), do: "room_here:#{room}"

  @doc "Shows `human` as here in `room` while the calling process lives."
  def join(room, human),
    do: track(self(), topic(room), Integer.to_string(human.human_account_id), human.person)

  @doc "Stops showing the calling process in `room`."
  def leave(room, human),
    do: untrack(self(), topic(room), Integer.to_string(human.human_account_id))

  @doc """
  Everyone in `room`, as `%{id: account_id, name, wallet, ens_name}`
  (`AshTemplate.PublicIdentity.person/1`), ordered by name.
  """
  def people(room) do
    topic(room)
    |> list()
    |> Enum.map(fn {id, %{metas: [meta | _]}} -> person(id, meta) end)
    |> Enum.sort_by(&String.downcase(AshTemplate.PublicIdentity.words(&1)))
  end

  @impl Phoenix.Presence
  def init(_opts), do: {:ok, %{}}

  # A person who opens another tab arrives again, which a page that lists them
  # already takes as no change; they leave once their last tab closes.
  @impl Phoenix.Presence
  def handle_metas("room_people:" <> room, %{joins: joins, leaves: leaves}, presences, state) do
    arrived = for {id, %{metas: [meta | _]}} <- joins, do: person(id, meta)
    left = for {id, _presence} <- leaves, not is_map_key(presences, id), do: String.to_integer(id)

    if arrived != [] or left != [],
      do:
        Phoenix.PubSub.local_broadcast(
          AshTemplate.PubSub,
          here_topic(room),
          {:here, room, arrived, left}
        )

    {:ok, state}
  end

  defp person(id, meta),
    do: meta |> Map.take([:name, :wallet, :ens_name]) |> Map.put(:id, String.to_integer(id))
end
