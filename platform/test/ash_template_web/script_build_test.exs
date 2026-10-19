defmodule AshTemplateWeb.ScriptBuildTest do
  # Builds the site's scripts exactly as `mix assets.build` does (after `mix
  # setup`) and reads esbuild's own account of the build.
  #
  # Regressions: esbuild's shared pieces were sent with "public" alone, so every
  # return visit asked for each one again; the lab pages' hooks, the WebMCP tools
  # and viem's whole entry point were in the script every page loads first.
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test, only: [conn: 2]

  # The script every page loads first, unminified; it was 1,149,694 bytes on 19 Oct.
  @first_load_budget 1_200_000
  @loaded_elsewhere ~w(js/lab_pages.ts js/showcase.ts js/motion_lab.ts js/site_buttons_lab.ts js/public_tools.ts)

  setup_all do
    metafile = Path.join(Mix.Project.build_path(), "script-build.json")
    0 = Esbuild.run(:ash_template, ["--metafile=" <> metafile, "--log-level=warning"])
    outputs = (metafile |> File.read!() |> Jason.decode!())["outputs"]
    [app] = outputs |> Map.keys() |> Enum.filter(&String.ends_with?(&1, "/assets/js/app.js"))

    %{outputs: outputs, first_load: first_load(outputs, [app], [])}
  end

  test "every shared piece is kept for a year", %{outputs: outputs, first_load: first_load} do
    # The two entry scripts, and the styles app.js's own imports bring with them.
    pieces = outputs |> Map.keys() |> Enum.reject(&String.ends_with?(&1, ~w(/js/app.js /js/app.css /js/privy_bridge.js)))

    assert pieces != []
    assert Enum.all?(pieces, &String.contains?(&1, "/assets/js/chunks/"))

    piece = first_load |> Enum.find(&String.contains?(&1, "/chunks/")) |> Path.basename()
    response = conn(:get, "/assets/js/chunks/" <> piece) |> AshTemplateWeb.Endpoint.call([])

    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "the first script holds no lab hooks, WebMCP tools or viem's whole entry point",
       %{outputs: outputs, first_load: first_load} do
    sources = Enum.flat_map(first_load, &Map.keys(outputs[&1]["inputs"]))

    assert "js/app.ts" in sources
    assert Enum.filter(sources, &(&1 in @loaded_elsewhere or String.starts_with?(&1, "js/hooks/crown"))) == []
    refute Enum.any?(sources, &String.ends_with?(&1, "node_modules/viem/_esm/index.js"))

    assert first_load |> Enum.map(&outputs[&1]["bytes"]) |> Enum.sum() <= @first_load_budget
  end

  # The files a page fetches before app.js can run: app.js and every file it
  # imports statically, transitively. Dynamic imports load later, where used.
  defp first_load(_outputs, [], seen), do: seen

  defp first_load(outputs, [file | rest], seen) do
    if file in seen do
      first_load(outputs, rest, seen)
    else
      imported = for %{"kind" => "import-statement", "path" => path} <- outputs[file]["imports"], do: path
      first_load(outputs, rest ++ imported, [file | seen])
    end
  end
end
