defmodule AshTemplateWeb.ScriptBuildTest do
  # Builds the site's scripts as `mix assets.build` does (after `mix assets.setup`),
  # with its copy tasks and esbuild profile, in a folder of its own under the build
  # path, and reads esbuild's own account of the build. `make check` runs `mix test`
  # beside `mix precommit`, whose copy tasks rewrite assets/vendor and whose browser
  # walk serves priv/static/assets: this build reads neither, and of the walk's
  # folder it writes only the one piece it asks the endpoint for.
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
    # The platform folder's layout, so the build's own paths (../priv/static/assets/js,
    # ../../priv/tool_manifest.json) land inside it, and its packages are still found in
    # platform/node_modules above it.
    root = Path.join(Mix.Project.build_path(), "script-build")
    assets = Path.join(root, "assets")
    File.rm_rf!(root)

    for source <- ~w(assets/js assets/css assets/tsconfig.json priv/tool_manifest.json) do
      File.mkdir_p!(Path.dirname(Path.join(root, source)))
      File.cp_r!(source, Path.join(root, source))
    end

    # The copy tasks `mix assets.build` runs, each writing under the folder it runs in.
    copy_tasks = Enum.filter(Mix.Project.config()[:aliases][:"assets.build"], &String.ends_with?(&1, ".assets"))
    File.cd!(root, fn -> Enum.each(copy_tasks, &Mix.Task.rerun/1) end)

    profile = Keyword.put(Application.fetch_env!(:esbuild, :ash_template), :cd, assets)
    Application.put_env(:esbuild, :script_build_test, profile)
    on_exit(fn -> Application.delete_env(:esbuild, :script_build_test) end)
    metafile = Path.join(root, "script-build.json")
    0 = Esbuild.run(:script_build_test, ["--metafile=" <> metafile, "--log-level=warning"])
    outputs = (metafile |> File.read!() |> Jason.decode!())["outputs"]
    [app] = outputs |> Map.keys() |> Enum.filter(&String.ends_with?(&1, "/assets/js/app.js"))

    %{root: root, outputs: outputs, first_load: first_load(outputs, [app], [])}
  end

  test "every shared piece is kept for a year", %{root: root, outputs: outputs, first_load: first_load} do
    # The two entry scripts, and the styles app.js's own imports bring with them.
    pieces = outputs |> Map.keys() |> Enum.reject(&String.ends_with?(&1, ~w(/js/app.js /js/app.css /js/privy_bridge.js)))

    assert pieces != []
    assert Enum.all?(pieces, &String.contains?(&1, "/assets/js/chunks/"))

    # A piece's name carries its content's hash, so the rename can only replace a file
    # holding the same bytes, and the piece lands whole for a walk serving the folder.
    piece = first_load |> Enum.find(&String.contains?(&1, "/chunks/")) |> Path.basename()
    served = Application.app_dir(:ash_template, "priv/static/assets/js/chunks")
    landing = Path.join(served, ".#{piece}.#{System.pid()}")
    File.mkdir_p!(served)
    File.cp!(Path.join([root, "priv/static/assets/js/chunks", piece]), landing)
    File.rename!(landing, Path.join(served, piece))
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
