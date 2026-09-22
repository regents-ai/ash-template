defmodule AshTemplateWeb.ConnCase do
  @moduledoc "Connection and LiveView test support without a database sandbox."

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint AshTemplateWeb.Endpoint

      use AshTemplateWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest, except: [build_conn: 0, init_test_session: 2]
      import Phoenix.LiveViewTest
      import AshTemplateWeb.SessionAuthorityHelpers
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: AshTemplateWeb.SessionAuthorityHelpers.build_conn()}
  end
end
