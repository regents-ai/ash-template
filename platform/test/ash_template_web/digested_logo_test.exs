defmodule AshTemplateWeb.DigestedLogoTest do
  # Regression: the header logo's path was built as a plain string, so it never
  # took its digested name and every return visit fetched both logos again. A
  # release reads the digested names from the manifest into the endpoint's static
  # cache; this puts the same entries there, so it shares the endpoint's cache
  # with every other test and runs alone.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint AshTemplateWeb.Endpoint
  @logos %{
    "/images/brand/mark-flat-light.svg" => "/images/brand/mark-flat-light-0123456789abcdef.svg?vsn=d",
    "/images/brand/mark-flat-dark.svg" => "/images/brand/mark-flat-dark-0123456789abcdef.svg?vsn=d"
  }

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)

    for {path, digested} <- @logos do
      Phoenix.Config.cache(@endpoint, {:__phoenix_static__, path}, fn _ -> {:cache, {digested, nil}} end)
    end

    on_exit(fn ->
      Phoenix.Config.clear_cache(@endpoint)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "the header logo goes by its digested name" do
    html = build_conn() |> get("/app") |> html_response(200)

    for digested <- Map.values(@logos), do: assert(html =~ ~s(src="#{digested}"))
  end
end
