defmodule AshTemplateWeb.HarbourLiveTest do
  # The agent harbour in the motion lab: each island has its own page, an agent's
  # card opens from its address, and each move sends one agent to another island
  # and lists it first on its card. Closing a card and the drawing are checked in
  # the browser.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [assert_error_sent: 2, build_conn: 0, get: 2, html_response: 2]

  alias AshTemplateWeb.HarbourLive

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "each island's page marks its island current, and an island that does not exist is not found" do
    for place <- ~w(inn forge castle) do
      assert current_links(page("/animations/harbour/#{place}")) == ["/animations/harbour/#{place}"]
    end

    assert current_links(page("/animations/harbour")) == []
    assert_error_sent(404, fn -> get(build_conn(), "/animations/harbour/lighthouse") end)
  end

  test "an agent's address puts its card on the page, and an agent who is not there gets none" do
    html = page("/animations/harbour/forge?agent=basil")
    assert html =~ ~s(id="harbour-agent")
    assert html =~ ~s(<h2 id="harbour-agent-title">Basil</h2>)
    assert html =~ "Work at the Forge"

    refute page("/animations/harbour?agent=nobody") =~ ~s(id="harbour-agent")
  end

  test "each move sends one agent to another island, listed first on its card, four at most" do
    {:ok, socket} = HarbourLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    ids = Enum.map(socket.assigns.crew, & &1.id)

    socket = Enum.reduce(1..13, socket, fn _move, socket -> move(socket) end)

    assert Enum.map(socket.assigns.crew, & &1.id) == ids
  end

  # One move: exactly one agent changes, to another island, with that island
  # first among its actions and the three before it kept.
  defp move(socket) do
    before = socket.assigns.crew
    {:noreply, socket} = HarbourLive.handle_info(:act, socket)

    assert [{old, moved}] =
             before |> Enum.zip(socket.assigns.crew) |> Enum.reject(fn {old, now} -> old == now end)

    assert moved.id == old.id
    assert moved.place != old.place
    assert [%{place: place} | earlier] = moved.actions
    assert place == moved.place
    assert earlier == Enum.take(old.actions, 3)
    socket
  end

  defp page(path), do: build_conn() |> get(path) |> html_response(200)

  # Where each link the page marks as the current one goes.
  defp current_links(html) do
    for [tag] <- Regex.scan(~r/<a\b[^>]*>/, html),
        tag =~ ~s(aria-current="page"),
        [_, href] <- Regex.scan(~r/\bhref="([^"]*)"/, tag),
        do: href
  end
end
