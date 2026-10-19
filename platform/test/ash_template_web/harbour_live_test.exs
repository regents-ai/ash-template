defmodule AshTemplateWeb.HarbourLiveTest do
  # The agent harbour in the motion lab: each island has its own page, an agent's
  # card opens from its address, and each move sends one agent to another island
  # and lists it first on its card. What the page shows, the cards, the list under
  # the harbour and pressing on the sea are checked in the browser
  # (test/browser/harbour.spec.ts, test/browser/harbour_sea.spec.ts).
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

  test "each island has its own page, and an island that does not exist is not found" do
    for place <- ~w(inn forge castle) do
      assert build_conn() |> get("/animations/harbour/#{place}") |> html_response(200)
      assert params(%{"place" => place}).place.id == place
    end

    assert params(%{}).place == nil
    assert_raise AshTemplateWeb.NotFoundError, fn -> params(%{"place" => "lighthouse"}) end
    assert_error_sent(404, fn -> get(build_conn(), "/animations/harbour/lighthouse") end)
  end

  test "an agent's address opens its card, and an agent who is not there opens none" do
    assert params(%{"place" => "forge", "agent" => "basil"}).agent_id == "basil"
    assert params(%{"agent" => "nobody"}).agent_id == nil
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

  # The page's assigns once it has read an address's parameters.
  defp params(params) do
    {:ok, socket} = HarbourLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, socket} = HarbourLive.handle_params(params, "http://localhost/animations/harbour", socket)
    socket.assigns
  end
end
