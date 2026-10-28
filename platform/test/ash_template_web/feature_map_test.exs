defmodule AshTemplateWeb.FeatureMapTest do
  # The browser walk opens every page and document in test/browser/pages.json. A
  # page added to the router without an entry there would never be walked, and an
  # agent added to the pairing box would get a page nobody opens.
  use ExUnit.Case, async: true

  @map "test/browser/pages.json" |> File.read!() |> Jason.decode!()

  # Machine interfaces, each proved by its own tests rather than by a page walk.
  @interfaces ["/api/", "/auth/", "/oauth/", "/admin/", "/.well-known/oauth-"]

  test "every page and document the router serves is in the walk, and nothing else" do
    served =
      for %{verb: :get, path: path} <- AshTemplateWeb.Router.__routes__(),
          not String.starts_with?(path, @interfaces),
          into: MapSet.new(),
          do: path

    walked = MapSet.new(@map["pages"] ++ @map["documents"], & &1["route"])

    # Each list names the routes to add to, or remove from, the walk.
    assert served |> MapSet.difference(walked) |> Enum.sort() == []
    assert walked |> MapSet.difference(served) |> Enum.sort() == []
  end

  test "the walk opens every agent's page and skill" do
    agents = AshTemplateWeb.AgentGuides.paths() -- ["/agents"]

    assert paths("/agents/:agent") == agents
    assert paths("/agents/:agent/skill.md") == Enum.map(agents, &(&1 <> "/skill.md"))
  end

  defp paths(route),
    do: Enum.find(@map["pages"] ++ @map["documents"], &(&1["route"] == route))["paths"]
end
