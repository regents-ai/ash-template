defmodule AshTemplateWeb.PageTokenTest do
  # A connected page whose signed token lacks the client key is not a crash: both
  # hooks that read the key (AshTemplateWeb.Live.Session, AshTemplateWeb.Live.OpenPages)
  # halt and ask for one full request of the page the token names, or of the public
  # root when it names none.
  use ExUnit.Case, async: true

  alias AshTemplateWeb.Live.{OpenPages, Session}
  alias Phoenix.LiveView.{Lifecycle, Socket}

  defp connected,
    do: %Socket{
      router: AshTemplateWeb.Router,
      transport_pid: self(),
      private: %{lifecycle: %Lifecycle{}}
    }

  for {name, hook} <- [session: {Session, :load_human}, open_pages: {OpenPages, :default}] do
    @hook hook

    test "#{name}: a token without the client key asks for the page again" do
      {module, stage} = @hook
      session = %{"_csrf_token" => "form-token", "render_route" => "/rooms/general?page=2"}

      assert {:halt, %Socket{redirected: {:redirect, %{to: "/rooms/general?page=2"}}}} =
               module.on_mount(stage, %{}, session, connected())

      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} =
               module.on_mount(stage, %{}, %{}, connected())
    end
  end
end
