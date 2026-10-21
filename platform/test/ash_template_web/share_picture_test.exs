defmodule AshTemplateWeb.SharePictureTest do
  # Regression: shared links showed mark.png, a 1024 x 512 crown, by a plain
  # path, so X kept its first copy of the picture for good. The picture is now
  # named by its digested address, and the size the page gives is the picture's
  # own. A release reads the digested names from the manifest into the
  # endpoint's static cache; this puts the same entry there, so it shares the
  # endpoint's cache with every other test and runs alone.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint AshTemplateWeb.Endpoint
  @picture "/images/og-image.png"
  @digested "/images/og-image-0123456789abcdef.png?vsn=d"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    Phoenix.Config.cache(@endpoint, {:__phoenix_static__, @picture}, fn _ -> {:cache, {@digested, nil}} end)

    on_exit(fn ->
      Phoenix.Config.clear_cache(@endpoint)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "shared links name the picture by its digested address, at its own size" do
    html = build_conn() |> get("/") |> html_response(200)
    url = @endpoint.url() <> @digested

    assert html =~ ~s(<meta property="og:image" content="#{url}">)
    assert html =~ ~s(<meta name="twitter:image" content="#{url}">)

    <<_signature::binary-8, _length::32, "IHDR", width::32, height::32, _rest::binary>> =
      File.read!(Path.join(:code.priv_dir(:ash_template), "static" <> @picture))

    assert {width, height} == {1200, 630}
    assert html =~ ~s(<meta property="og:image:width" content="#{width}">)
    assert html =~ ~s(<meta property="og:image:height" content="#{height}">)
  end
end
