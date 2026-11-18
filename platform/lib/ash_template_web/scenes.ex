defmodule AshTemplateWeb.Scenes do
  @moduledoc """
  The five numbered scenes: each one's title, whether its action is Action or Chill,
  its line, its rarity score and every trait it was dealt (category, trait, tier and
  share), in the order its trait list gives them, with "None" and "Nothing" kept as
  dealt. The Scenes page (`AshTemplateWeb.ScenesLabLive`), each scene's own page and
  its trait file (`AshTemplateWeb.SceneController`) all read them from here.

  Each scene is baked into `priv/static/splats/<name>.bin`, with its stills
  `priv/static/images/animations/splats-<name>-wide.png` (480 by 320) and
  `-square.png` (360 by 360). Its sky is the colour its scene file clears to (the
  palette entry the header names as the backdrop, `assets/js/splats/studio/FORMAT.md`),
  read here as the module compiles, so a scene's own page sits on that sky round the
  still whatever the shape of the frame it is shown in.
  """

  use AshTemplateWeb, :verified_routes

  alias AshTemplateWeb.{Endpoint, NotFoundError, PublicDocuments}

  # The traits shown as tags under each scene, in this order.
  @headline ~w(World Ground Resident Landmark Hour)

  # Each scene as its trait list deals it: {category, trait, tier, share}.
  @scenes [
    %{
      number: 1,
      name: "campfire-stories",
      title: "Campfire Stories",
      kind: "Chill",
      description: "A circle, a fire, one of them telling it with their hands.",
      rarity: 1459.5,
      traits: [
        {"Action", "Campfire Stories", "Epic", "0.90%"},
        {"World", "Robot Factory", "Common", "9.91%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Icicles", "Uncommon", "3.60%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Blue Hour", "Common", "11.26%"},
        {"Weather", "Rainbow", "Rare", "2.25%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "Halftone", "Rare", "2.70%"},
        {"Era", "1989 Camcorder", "Uncommon", "3.60%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "Robot Head", "Rare", "1.35%"},
        {"Flora", "Lotus", "Rare", "1.80%"},
        {"Water", "Lava", "Rare", "2.70%"},
        {"Machine", "Chain Reaction", "Epic", "0.90%"},
        {"Cargo", "Books", "Rare", "1.80%"},
        {"Home", "Aquarium", "Rare", "1.35%"},
        {"Relic", "Power Glove", "Epic", "0.45%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "INSERT COIN", "Rare", "1.80%"},
        {"Resident", "Night Owl", "Rare", "1.13%"},
        {"Skin", "Robot", "Uncommon", "4.50%"},
        {"Headwear", "Flower Crown", "Rare", "1.35%"},
        {"Eyes", "Glowing", "Rare", "1.80%"},
        {"Companion", "Frog", "Rare", "1.35%"},
        {"Light", "Traffic Light", "Rare", "1.13%"},
        {"Drift", "Snowflakes", "Uncommon", "4.50%"},
        {"Motion", "Bob", "Common", "9.01%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 2,
      name: "trainer-battle",
      title: "Trainer Battle",
      kind: "Action",
      description: "Two small monsters square up; one throws a spark.",
      rarity: 1582.1,
      traits: [
        {"Action", "Trainer Battle", "Epic", "0.68%"},
        {"World", "Terraformed Crater", "Epic", "0.90%"},
        {"Ground", "Twenty-Sided Die", "Rare", "1.13%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Charcoal", "Common", "32.21%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Dots", "Rare", "1.13%"},
        {"Finish", "Wireframe", "Rare", "1.80%"},
        {"Era", "1999 Y2K", "Uncommon", "5.41%"},
        {"Camera", "Front And Centre", "Uncommon", "4.50%"},
        {"Landmark", "Castle Keep", "Rare", "1.80%"},
        {"Flora", "Corn Rows", "Epic", "0.90%"},
        {"Water", "Pond", "Common", "9.01%"},
        {"Machine", "Cryo Pods", "Rare", "1.13%"},
        {"Cargo", "Newspapers", "Epic", "0.90%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "Map With An X", "Rare", "1.80%"},
        {"Vehicle", "Bicycle", "Rare", "2.70%"},
        {"Sign", "FEW", "Epic", "0.45%"},
        {"Resident", "Swamp Toad", "Rare", "1.13%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Wide", "Uncommon", "3.60%"},
        {"Companion", "Spider", "Epic", "0.68%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Smoke", "Uncommon", "3.60%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "On The Resident", "Uncommon", "6.76%"}
      ]
    },
    %{
      number: 3,
      name: "missile-circus",
      title: "Missile Circus",
      kind: "Action",
      description: "A swarm of missiles on curling smoke trails chases one dodging flyer.",
      rarity: 1480.7,
      traits: [
        {"Action", "Missile Circus", "Epic", "0.68%"},
        {"World", "Drive-In", "Rare", "1.35%"},
        {"Ground", "Snow Globe", "Rare", "1.35%"},
        {"Underside", "Hanging Garden", "Uncommon", "3.15%"},
        {"Sky", "Grid Horizon", "Rare", "2.70%"},
        {"Orbit", "Red Balloon", "Rare", "1.13%"},
        {"Hour", "Midnight", "Common", "13.51%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Trapper Keeper", "Rare", "1.13%"},
        {"Finish", "No Outline", "Uncommon", "5.41%"},
        {"Era", "1994 Rental", "Uncommon", "4.50%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "Radio Dish", "Rare", "1.80%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "Record Player", "Rare", "2.25%"},
        {"Relic", "Pocket Watch", "Epic", "0.90%"},
        {"Vehicle", "Jet Pack", "Epic", "0.68%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Robot Arm Crew", "Common", "8.11%"},
        {"Skin", "Shadow", "Rare", "1.13%"},
        {"Headwear", "Bowler", "Epic", "0.68%"},
        {"Eyes", "Headset", "Rare", "1.35%"},
        {"Companion", "Frog", "Rare", "1.35%"},
        {"Light", "Lighthouse Beam", "Rare", "1.80%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Pulse", "Uncommon", "5.41%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Constellation", "Uncommon", "6.76%"}
      ]
    },
    %{
      number: 4,
      name: "fishing",
      title: "Fishing",
      kind: "Chill",
      description: "A line in the water and a bite that never comes.",
      rarity: 1507.9,
      traits: [
        {"Action", "Fishing", "Rare", "1.80%"},
        {"World", "Orbital Greenhouse", "Rare", "1.80%"},
        {"Ground", "Black Slab", "Epic", "0.45%"},
        {"Underside", "Anchor Chain", "Uncommon", "3.15%"},
        {"Sky", "Smog", "Rare", "2.25%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Technicolor", "Rare", "1.80%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "2012 Reblog", "Rare", "2.70%"},
        {"Camera", "Dutch Tilt", "Rare", "2.70%"},
        {"Landmark", "Black Slab", "Epic", "0.90%"},
        {"Flora", "Kelp Forest", "Rare", "1.35%"},
        {"Water", "Hot Spring", "Rare", "2.25%"},
        {"Machine", "Clone Vats", "Epic", "0.90%"},
        {"Cargo", "Fireworks", "Epic", "0.90%"},
        {"Home", "Floor Lamp", "Uncommon", "3.15%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "24 HRS", "Rare", "1.13%"},
        {"Resident", "Dragon", "Epic", "0.68%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "Wizard Hat", "Rare", "1.35%"},
        {"Eyes", "Wide", "Uncommon", "3.60%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Feathers", "Rare", "1.35%"},
        {"Motion", "Circle", "Uncommon", "4.50%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Reflection", "Uncommon", "4.50%"}
      ]
    },
    %{
      number: 5,
      name: "meteor-strike",
      title: "Meteor Strike",
      kind: "Action",
      description: "A rock falls from the sky and is batted away at the last moment.",
      rarity: 1604.7,
      traits: [
        {"Action", "Meteor Strike", "Epic", "0.68%"},
        {"World", "Coral Reef", "Rare", "2.25%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Jellyfish Trails", "Epic", "0.90%"},
        {"Sky", "Starfield", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Noon", "Common", "19.82%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Punk Teal", "Rare", "1.35%"},
        {"Finish", "Glitch", "Rare", "1.80%"},
        {"Era", "1977 Disco", "Uncommon", "3.60%"},
        {"Camera", "Isometric", "Common", "8.11%"},
        {"Landmark", "Black Slab", "Epic", "0.90%"},
        {"Flora", "Bonsai", "Uncommon", "3.60%"},
        {"Water", "Quicksand", "Epic", "0.90%"},
        {"Machine", "Tape Reel Computer", "Rare", "1.80%"},
        {"Cargo", "Fish Crates", "Epic", "0.90%"},
        {"Home", "Couch", "Uncommon", "4.50%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "Walking House", "Epic", "0.45%"},
        {"Sign", "OPEN", "Uncommon", "3.60%"},
        {"Resident", "Big Grey Neighbour", "Epic", "0.45%"},
        {"Skin", "Chrome", "Rare", "1.80%"},
        {"Headwear", "Hood Up", "Rare", "2.25%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "Cat", "Uncommon", "3.60%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Snowflakes", "Uncommon", "4.50%"},
        {"Motion", "Rise", "Uncommon", "3.60%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    }
  ]

  # A scene file's header: "RSPL", fourteen whole numbers, the last the backdrop's
  # palette index, then twenty-eight floats; the palette's 0xRRGGBB words follow.
  splats = Application.app_dir(:ash_template, "priv/static/splats")

  sky = fn name ->
    file = Path.join(splats, name <> ".bin")
    Module.put_attribute(__MODULE__, :external_resource, file)
    bytes = File.read!(file)
    <<backdrop::little-32>> = binary_part(bytes, 56, 4)
    <<colour::little-32>> = binary_part(bytes, 284 + 4 * backdrop, 4)
    "#" <> (colour |> Integer.to_string(16) |> String.pad_leading(6, "0") |> String.downcase())
  end

  @scenes for %{traits: traits} = scene <- @scenes,
              do:
                Map.merge(scene, %{
                  sky: sky.(scene.name),
                  traits:
                    for(
                      {category, trait, tier, share} <- traits,
                      do: %{category: category, trait: trait, tier: tier, share: share}
                    )
                })

  @doc "Every scene, numbered 1 to 5, in order."
  def all, do: @scenes

  @doc ~s(The scene an address numbers, "1" to "5"; any other answers the site's 404.)
  def fetch!(number) do
    Enum.find(@scenes, &(Integer.to_string(&1.number) == number)) || raise NotFoundError
  end

  @doc "The traits shown as tags under a scene: World, Ground, Resident, Landmark and Hour."
  def headline(scene), do: for(category <- @headline, do: trait(scene, category))

  defp trait(scene, category), do: Enum.find(scene.traits, &(&1.category == category))

  @doc "A scene's baked file, on this site."
  def file(scene), do: Endpoint.static_path("/splats/#{scene.name}.bin")

  @doc "A scene's still, `:wide` (480 by 320) or `:square` (360 by 360), on this site."
  def still(scene, shape), do: Endpoint.static_path(still_path(scene, shape))

  @doc """
  A scene's still at its full public address. It names the file itself, not this
  release's fingerprinted copy, so an address kept elsewhere still works after the
  next release.
  """
  def still_url(scene, shape), do: PublicDocuments.url(still_path(scene, shape))

  defp still_path(scene, shape) when shape in [:wide, :square],
    do: "/images/animations/splats-#{scene.name}-#{shape}.png"

  @doc "A scene's own page: the scene alone, at its full public address."
  def page_url(scene), do: PublicDocuments.url(~p"/scenes/#{scene.number}")

  @doc """
  A scene's trait file: its title and line, its square still, its own page, the
  Scenes page, and every trait as a `trait_type` and `value`, in the data's order.
  Every address is the site's full public one.
  """
  def metadata(scene) do
    %{
      name: scene.title,
      description: scene.description,
      image: still_url(scene, :square),
      animation_url: page_url(scene),
      external_url: PublicDocuments.url(~p"/animations/scenes"),
      attributes: for(t <- scene.traits, do: %{trait_type: t.category, value: t.trait})
    }
  end
end
