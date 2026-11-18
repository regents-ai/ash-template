defmodule AshTemplateWeb.ScenesTest do
  # The five scenes: the Scenes page, each scene's own page, which any site may frame,
  # and its trait file, which any site may read; and the scene files a frame with no
  # origin of its own fetches. What the pages draw, and a scene inside another site's
  # sandboxed frame, are checked in the browser (test/browser/scenes.spec.ts).
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [assert_error_sent: 2, build_conn: 0, get: 2]
  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test, only: [conn: 2]

  alias AshTemplateWeb.{ContentSecurityPolicy, Endpoint, Scenes}

  @endpoint Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "each trait file names its scene, its pictures and pages by full address, and every trait in order" do
    for scene <- Scenes.all() do
      response = request("/scenes/#{scene.number}/metadata.json")

      assert response.status == 200
      assert get_resp_header(response, "access-control-allow-origin") == ["*"]
      metadata = Jason.decode!(response.resp_body)

      assert Map.keys(metadata) ==
               ~w(animation_url attributes description external_url image name)

      assert metadata["name"] == scene.title
      assert metadata["description"] == scene.description

      assert metadata["image"] ==
               "#{Endpoint.url()}/images/animations/splats-#{scene.name}-square.png"

      assert metadata["animation_url"] == "#{Endpoint.url()}/scenes/#{scene.number}"
      assert metadata["external_url"] == "#{Endpoint.url()}/animations/scenes"

      assert metadata["attributes"] ==
               for(t <- scene.traits, do: %{"trait_type" => t.category, "value" => t.trait})

      assert length(metadata["attributes"]) == 31

      # Each address answers: the picture is the square still, the page the scene's own.
      assert %{status: 200} = image = request(path(metadata["image"]))
      assert get_resp_header(image, "content-type") == ["image/png"]
      assert request(path(metadata["animation_url"])).status == 200
      assert request(path(metadata["external_url"])).status == 200
    end
  end

  test "a scene's own page may be framed by any site; the pages beside it keep their policies" do
    page = request("/scenes/1")

    assert page.status == 200
    assert get_resp_header(page, "content-security-policy") == [ContentSecurityPolicy.scene()]
    assert ContentSecurityPolicy.scene() =~ "frame-ancestors *"
    assert get_resp_header(page, "x-frame-options") == []
    refute Enum.any?(get_resp_header(page, "set-cookie"), &(&1 =~ session_cookie()))

    scenes = request("/animations/scenes")
    assert get_resp_header(scenes, "content-security-policy") == [ContentSecurityPolicy.sign_in()]
    assert ContentSecurityPolicy.sign_in() =~ "frame-ancestors 'none'"

    traits = request("/scenes/1/metadata.json")
    assert get_resp_header(traits, "content-security-policy") == [ContentSecurityPolicy.reading()]
    assert get_resp_header(scenes, "access-control-allow-origin") == []
    assert get_resp_header(page, "access-control-allow-origin") == []
  end

  test "a scene's own page loads its one classic script, its stylesheet and its scene by full address" do
    page = "/scenes/2" |> request() |> Map.fetch!(:resp_body) |> LazyHTML.from_document()
    full = Endpoint.static_url()

    assert [script] = page |> LazyHTML.query("script[src]") |> LazyHTML.attribute("src")
    assert script == full <> Endpoint.static_path("/assets/js/scene_page.js")
    assert page |> LazyHTML.query("script[type=module]") |> Enum.count() == 0

    assert [stylesheet] =
             page |> LazyHTML.query("link[rel=stylesheet]") |> LazyHTML.attribute("href")

    assert stylesheet == full <> Endpoint.static_path("/assets/js/scene_page.css")

    assert page |> LazyHTML.query("[data-splats-file]") |> LazyHTML.attribute("data-splats-file") ==
             [full <> Endpoint.static_path("/splats/trainer-battle.bin")]

    assert page |> LazyHTML.query("button[data-splats-zoom]") |> Enum.count() == 3
    assert page |> LazyHTML.query("[id$=-gif]") |> Enum.count() == 0

    assert page |> LazyHTML.query(~s(meta[name="twitter:card"])) |> LazyHTML.attribute("content") ==
             ["summary_large_image"]

    assert page |> LazyHTML.query(~s(meta[property="og:image"])) |> LazyHTML.attribute("content") ==
             ["#{Endpoint.url()}/images/animations/splats-trainer-battle-wide.png"]
  end

  test "only the scene files may be read from any origin" do
    scene = request("/splats/campfire-stories.bin")

    assert scene.status == 200
    assert get_resp_header(scene, "access-control-allow-origin") == ["*"]
    assert get_resp_header(scene, "x-frame-options") == ["DENY"]

    still = request("/images/animations/splats-campfire-stories-wide.png")
    assert still.status == 200
    assert get_resp_header(still, "access-control-allow-origin") == []
  end

  test "the Scenes page shows the five scenes, each with its stage, tags, traits and links" do
    page = "/animations/scenes" |> request() |> Map.fetch!(:resp_body) |> LazyHTML.from_document()

    assert page |> LazyHTML.query("article") |> Enum.count() == 5

    for scene <- Scenes.all() do
      card = "#scene-#{scene.number}"
      assert page |> LazyHTML.query("#{card}[data-splats-file]") |> Enum.count() == 1
      assert page |> LazyHTML.query("#{card}-gif button") |> Enum.count() == 1
      assert page |> LazyHTML.query("#{card}-traits tbody tr") |> Enum.count() == 31

      assert page
             |> LazyHTML.query(~s(a[href="/scenes/#{scene.number}"][target=_blank]))
             |> Enum.count() == 1
    end
  end

  test "a number with no scene is not found, on its page and its trait file" do
    for path <- ["/scenes/6", "/scenes/0/metadata.json", "/scenes/one"] do
      assert_error_sent 404, fn -> get(build_conn(), path) end
    end
  end

  defp request(path), do: :get |> conn(path) |> Endpoint.call(Endpoint.init([]))

  defp path(address), do: URI.parse(address).path

  defp session_cookie, do: Application.fetch_env!(:ash_template, :session_options)[:key]
end
