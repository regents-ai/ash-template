defmodule AshTemplateWeb.Scenes do
  @moduledoc """
  The numbered scenes: each one's title, whether its action is Action or Chill,
  its line, its rarity score and every trait it was dealt (category, trait, tier and
  share), in the order its trait list gives them, with "None" and "Nothing" kept as
  dealt. The Scenes page (`AshTemplateWeb.ScenesLabLive`), each scene's own page and
  its trait file (`AshTemplateWeb.SceneController`) all read them from here.

  Each scene is baked into `priv/static/splats/<name>.bin`, and `npm run stills:splats`
  draws its pictures from it into `priv/static/images/animations/`. The stages show its
  stills, `splats-<name>-wide.png` and `-square.png`, one pixel to an art pixel, so
  their size follows the size of the scene's art pixels: campfire-stories' are 480 by
  320 and 360 by 360. Other sites scale a small picture up smoothly, which blurs pixel
  art, so they get the same two at their stage's own size, every art pixel a hard-edged
  square:
  `-card.png` (1440 by 960), the link preview of the scene's own page, and `-item.png`
  (1080 by 1080), the picture its trait file names.

  Its sky is the colour its scene file clears to (the palette entry the header names
  as the backdrop, `assets/js/splats/studio/FORMAT.md`), read here as the module
  compiles, so a scene's own page sits on that sky round the still whatever the shape
  of the frame it is shown in.
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
    },
    %{
      number: 6,
      name: "dice-owl",
      title: "Dice Owl",
      kind: "Action",
      description: "An owl on a giant die bats a falling rock away at the last moment.",
      rarity: 712.4,
      traits: [
        {"Action", "Meteor Strike", "Epic", "0.68%"},
        {"World", "Terraformed Crater", "Epic", "0.90%"},
        {"Ground", "Twenty-Sided Die", "Rare", "1.13%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Charcoal", "Common", "32.21%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Technicolor", "Rare", "1.80%"},
        {"Finish", "No Outline", "Uncommon", "5.41%"},
        {"Era", "Timeless", "Common", "25.68%"},
        {"Camera", "Isometric", "Common", "8.11%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "Pond", "Common", "9.01%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Night Owl", "Rare", "1.13%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Glowing", "Rare", "1.80%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Reflection", "Uncommon", "4.50%"}
      ]
    },
    %{
      number: 7,
      name: "robot-toad",
      title: "Robot Toad",
      kind: "Chill",
      description: "A robot toad on a stump tells a story inside a snow globe.",
      rarity: 569.8,
      traits: [
        {"Action", "Campfire Stories", "Epic", "0.90%"},
        {"World", "Orbital Greenhouse", "Rare", "1.80%"},
        {"Ground", "Snow Globe", "Rare", "1.35%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Charcoal", "Common", "32.21%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Technicolor", "Rare", "1.80%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "Timeless", "Common", "25.68%"},
        {"Camera", "Dutch Tilt", "Rare", "2.70%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "None", "Common", "9.01%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Nothing", "Common", "13.51%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Swamp Toad", "Rare", "1.13%"},
        {"Skin", "Robot", "Uncommon", "4.50%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 8,
      name: "drive-in",
      title: "Drive-In",
      kind: "Chill",
      description: "A robot crew tells stories round a fire at a drive-in under the stars.",
      rarity: 610.0,
      traits: [
        {"Action", "Campfire Stories", "Epic", "0.90%"},
        {"World", "Drive-In", "Rare", "1.35%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Starfield", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Blue Hour", "Common", "11.26%"},
        {"Weather", "Rainbow", "Rare", "2.25%"},
        {"Palette", "Dots", "Rare", "1.13%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1994 Rental", "Uncommon", "4.50%"},
        {"Camera", "Isometric", "Common", "8.11%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Fireworks", "Epic", "0.90%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Robot Arm Crew", "Common", "8.11%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Smoke", "Uncommon", "3.60%"},
        {"Motion", "Still Life", "Uncommon", "6.76%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 9,
      name: "black-slab",
      title: "Black Slab",
      kind: "Action",
      description: "A robot crew bats a falling rock away from a drive-in on a black slab.",
      rarity: 912.3,
      traits: [
        {"Action", "Meteor Strike", "Epic", "0.68%"},
        {"World", "Drive-In", "Rare", "1.35%"},
        {"Ground", "Black Slab", "Epic", "0.45%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Charcoal", "Common", "32.21%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Noon", "Common", "19.82%"},
        {"Weather", "Rainbow", "Rare", "2.25%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "No Outline", "Uncommon", "5.41%"},
        {"Era", "1994 Rental", "Uncommon", "4.50%"},
        {"Camera", "Front And Centre", "Uncommon", "4.50%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "Pond", "Common", "9.01%"},
        {"Machine", "Cryo Pods", "Rare", "1.13%"},
        {"Cargo", "Fish Crates", "Epic", "0.90%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Robot Arm Crew", "Common", "8.11%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Snowflakes", "Uncommon", "4.50%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 10,
      name: "fishing-dragon",
      title: "Fishing Dragon",
      kind: "Chill",
      description: "A dragon fishes in a snow globe among the stars, and nothing bites.",
      rarity: 756.7,
      traits: [
        {"Action", "Fishing", "Rare", "1.80%"},
        {"World", "Terraformed Crater", "Epic", "0.90%"},
        {"Ground", "Snow Globe", "Rare", "1.35%"},
        {"Underside", "Anchor Chain", "Uncommon", "3.15%"},
        {"Sky", "Starfield", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1989 Camcorder", "Uncommon", "3.60%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "Castle Keep", "Rare", "1.80%"},
        {"Flora", "Bonsai", "Uncommon", "3.60%"},
        {"Water", "Pond", "Common", "9.01%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "Couch", "Uncommon", "4.50%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "OPEN", "Uncommon", "3.60%"},
        {"Resident", "Dragon", "Epic", "0.68%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Circle", "Uncommon", "4.50%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Reflection", "Uncommon", "4.50%"}
      ]
    },
    %{
      number: 11,
      name: "reef-owl",
      title: "Reef Owl",
      kind: "Chill",
      description: "An owl fishes off a flowering reef with its cat beside it; nothing bites.",
      rarity: 403.6,
      traits: [
        {"Action", "Fishing", "Rare", "1.80%"},
        {"World", "Coral Reef", "Rare", "2.25%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Charcoal", "Common", "32.21%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "Timeless", "Common", "25.68%"},
        {"Camera", "Front And Centre", "Uncommon", "4.50%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Night Owl", "Rare", "1.13%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "Cat", "Uncommon", "3.60%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Smoke", "Uncommon", "3.60%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 12,
      name: "missile-dragon",
      title: "Missile Dragon",
      kind: "Action",
      description: "A dragon dodges a swarm of missiles over a factory on a giant die.",
      rarity: 711.8,
      traits: [
        {"Action", "Missile Circus", "Epic", "0.68%"},
        {"World", "Robot Factory", "Common", "9.91%"},
        {"Ground", "Twenty-Sided Die", "Rare", "1.13%"},
        {"Underside", "Icicles", "Uncommon", "3.60%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Noon", "Common", "19.82%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Dots", "Rare", "1.13%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1989 Camcorder", "Uncommon", "3.60%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Bonsai", "Uncommon", "3.60%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "Bicycle", "Rare", "2.70%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Dragon", "Epic", "0.68%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Bob", "Common", "9.01%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 13,
      name: "snow-toad",
      title: "Snow Toad",
      kind: "Action",
      description: "A toad squares up to a rival in a snowy globe, and one throws a spark.",
      rarity: 781.2,
      traits: [
        {"Action", "Trainer Battle", "Epic", "0.68%"},
        {"World", "Robot Factory", "Common", "9.91%"},
        {"Ground", "Snow Globe", "Rare", "1.35%"},
        {"Underside", "Icicles", "Uncommon", "3.60%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Trapper Keeper", "Rare", "1.13%"},
        {"Finish", "Halftone", "Rare", "2.70%"},
        {"Era", "Timeless", "Common", "25.68%"},
        {"Camera", "Isometric", "Common", "8.11%"},
        {"Landmark", "Castle Keep", "Rare", "1.80%"},
        {"Flora", "Bonsai", "Uncommon", "3.60%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "Chain Reaction", "Epic", "0.90%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Swamp Toad", "Rare", "1.13%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Carved In Rock", "Common", "11.26%"}
      ]
    },
    %{
      number: 14,
      name: "striped-owl",
      title: "Striped Owl",
      kind: "Action",
      description: "A striped owl dodges a swarm of missiles round a greenhouse dome.",
      rarity: 647.3,
      traits: [
        {"Action", "Missile Circus", "Epic", "0.68%"},
        {"World", "Orbital Greenhouse", "Rare", "1.80%"},
        {"Ground", "Twenty-Sided Die", "Rare", "1.13%"},
        {"Underside", "Stalactites", "Common", "8.11%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "Halftone", "Rare", "2.70%"},
        {"Era", "1999 Y2K", "Uncommon", "5.41%"},
        {"Camera", "Front And Centre", "Uncommon", "4.50%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Night Owl", "Rare", "1.13%"},
        {"Skin", "Robot", "Uncommon", "4.50%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Snowflakes", "Uncommon", "4.50%"},
        {"Motion", "Bob", "Common", "9.01%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "On The Resident", "Uncommon", "6.76%"}
      ]
    },
    %{
      number: 15,
      name: "petal-storm",
      title: "Petal Storm",
      kind: "Action",
      description:
        "A robot crew stands in a meadow of flowers while petals storm past and two small monsters square up.",
      rarity: 481.4,
      traits: [
        {"Action", "Trainer Battle", "Epic", "0.68%"},
        {"World", "Coral Reef", "Rare", "2.25%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Anchor Chain", "Uncommon", "3.15%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Golden Hour", "Common", "15.77%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Rain Neon", "Rare", "2.48%"},
        {"Finish", "Halftone", "Rare", "2.70%"},
        {"Era", "Timeless", "Common", "25.68%"},
        {"Camera", "Dutch Tilt", "Rare", "2.70%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Robot Arm Crew", "Common", "8.11%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Plain", "Common", "31.08%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Petals", "Uncommon", "4.50%"},
        {"Motion", "Pulse", "Uncommon", "5.41%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "On The Resident", "Uncommon", "6.76%"}
      ]
    },
    %{
      number: 16,
      name: "chase",
      title: "Chase",
      kind: "Action",
      description:
        "Somebody runs the rim of the world with somebody else one step behind, for ever.",
      rarity: 1264.1,
      traits: [
        {"Action", "Chase", "Uncommon", "5.41%"},
        {"World", "Rain City Alley", "Rare", "2.70%"},
        {"Ground", "Asteroid", "Rare", "2.70%"},
        {"Underside", "Bare Rock", "Common", "33.33%"},
        {"Sky", "Storm Front", "Uncommon", "3.15%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Overcast Afternoon", "Uncommon", "6.76%"},
        {"Weather", "Thunderstorm", "Uncommon", "3.60%"},
        {"Palette", "Punk Zine", "Rare", "1.13%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1986 Saturday Morning", "Uncommon", "4.50%"},
        {"Camera", "Found Footage", "Rare", "1.13%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "None", "Common", "27.93%"},
        {"Cargo", "Comic Boxes", "Rare", "1.13%"},
        {"Home", "Couch", "Uncommon", "4.50%"},
        {"Relic", "Treasure Chest", "Uncommon", "3.15%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "OUT OF ORDER", "Rare", "1.13%"},
        {"Resident", "Stick Figure, Headphones", "Rare", "1.13%"},
        {"Skin", "Slime", "Rare", "1.13%"},
        {"Headwear", "Red Stepped Dome", "Epic", "0.45%"},
        {"Eyes", "Sunglasses", "Uncommon", "4.50%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Candles", "Uncommon", "3.15%"},
        {"Drift", "Embers", "Uncommon", "4.50%"},
        {"Motion", "Earthquake", "Epic", "0.68%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "On The Resident", "Uncommon", "6.76%"}
      ]
    },
    %{
      number: 17,
      name: "boulder-run",
      title: "Boulder Run",
      kind: "Action",
      description: "A runner stays one stride ahead of a rolling boulder.",
      rarity: 1306.8,
      traits: [
        {"Action", "Boulder Run", "Epic", "0.90%"},
        {"World", "Mall Food Court", "Rare", "2.25%"},
        {"Ground", "Turtle Shell", "Rare", "2.25%"},
        {"Underside", "Bare Rock", "Common", "33.33%"},
        {"Sky", "Blueprint", "Rare", "1.80%"},
        {"Orbit", "Flying Bicycle", "Epic", "0.45%"},
        {"Hour", "Midnight", "Common", "13.51%"},
        {"Weather", "Acid Rain", "Epic", "0.90%"},
        {"Palette", "Chrome Dust", "Rare", "1.80%"},
        {"Finish", "Mosaic", "Rare", "1.13%"},
        {"Era", "1982 Arcade", "Uncommon", "5.41%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Giant Mushrooms", "Uncommon", "3.15%"},
        {"Water", "Hot Spring", "Rare", "2.25%"},
        {"Machine", "Server Rack", "Rare", "2.25%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Shopkeeper", "Rare", "1.13%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "Cowboy Hat", "Rare", "1.80%"},
        {"Eyes", "Laser Eyes", "Rare", "1.13%"},
        {"Companion", "Horse", "Epic", "0.90%"},
        {"Light", "Daylight Only", "Common", "20.50%"},
        {"Drift", "Fireflies", "Uncommon", "6.76%"},
        {"Motion", "Flicker", "Uncommon", "6.76%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Reflection", "Uncommon", "4.50%"}
      ]
    },
    %{
      number: 18,
      name: "nap",
      title: "Nap",
      kind: "Chill",
      description: "Asleep in the best spot.",
      rarity: 1609.4,
      traits: [
        {"Action", "Nap", "Rare", "1.80%"},
        {"World", "Floating Island", "Common", "9.01%"},
        {"Ground", "Lily Pad", "Rare", "1.35%"},
        {"Underside", "Thrusters", "Uncommon", "3.60%"},
        {"Sky", "Milky Way", "Uncommon", "3.15%"},
        {"Orbit", "Ringed Planet", "Uncommon", "3.15%"},
        {"Hour", "Midnight", "Common", "13.51%"},
        {"Weather", "Clear", "Common", "40.99%"},
        {"Palette", "Doodle Pastel", "Rare", "1.35%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1977 Disco", "Uncommon", "3.60%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "Infinity Room", "Mythic", "0.23%"},
        {"Flora", "Kelp Forest", "Rare", "1.35%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "Claw Machine", "Rare", "1.35%"},
        {"Cargo", "Banana Bunch", "Epic", "0.90%"},
        {"Home", "Fridge", "Rare", "1.80%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "LAST GAS", "Epic", "0.90%"},
        {"Resident", "Robot Arm Crew", "Common", "8.11%"},
        {"Skin", "Slime", "Rare", "1.13%"},
        {"Headwear", "None", "Common", "27.03%"},
        {"Eyes", "Pixel Bar", "Epic", "0.68%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Moonbeam", "Rare", "1.80%"},
        {"Drift", "Dandelion Seeds", "Rare", "1.80%"},
        {"Motion", "Working Loop", "Common", "12.61%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Stencil On A Crate", "Common", "11.26%"}
      ]
    },
    %{
      number: 19,
      name: "stargazing",
      title: "Stargazing",
      kind: "Chill",
      description: "Lying back, pointing up.",
      rarity: 1213.7,
      traits: [
        {"Action", "Stargazing", "Rare", "1.80%"},
        {"World", "Teen Bedroom", "Rare", "2.70%"},
        {"Ground", "Floating Rock", "Common", "32.43%"},
        {"Underside", "Roots", "Common", "11.26%"},
        {"Sky", "Nebula", "Uncommon", "4.50%"},
        {"Orbit", "Nothing", "Common", "48.87%"},
        {"Hour", "Dawn", "Common", "9.91%"},
        {"Weather", "Heat Haze", "Rare", "2.70%"},
        {"Palette", "Gold Kiss", "Epic", "0.68%"},
        {"Finish", "Heavy Outline", "Uncommon", "6.76%"},
        {"Era", "2009 Indie Sleaze", "Rare", "2.25%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "Broadleaf Tree", "Common", "23.65%"},
        {"Water", "Koi Pond", "Uncommon", "3.15%"},
        {"Machine", "Robot Arms", "Common", "9.01%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "None", "Common", "27.25%"},
        {"Relic", "None", "Common", "52.03%"},
        {"Vehicle", "Raft", "Epic", "0.90%"},
        {"Sign", "None", "Common", "38.96%"},
        {"Resident", "Astronaut", "Uncommon", "3.15%"},
        {"Skin", "Static", "Epic", "0.68%"},
        {"Headwear", "Small Dish", "Epic", "0.45%"},
        {"Eyes", "Wide", "Uncommon", "3.60%"},
        {"Companion", "Bird", "Uncommon", "3.15%"},
        {"Light", "Spotlight", "Rare", "1.80%"},
        {"Drift", "Fireflies", "Uncommon", "6.76%"},
        {"Motion", "Rise", "Uncommon", "3.60%"},
        {"Anomaly", "Duplicate", "Rare", "1.13%"},
        {"Crown", "Flag", "Common", "14.64%"}
      ]
    },
    %{
      number: 20,
      name: "portal-opens",
      title: "Portal Opens",
      kind: "Action",
      description: "A ring of sparks widens and something steps through.",
      rarity: 987.2,
      traits: [
        {"Action", "Portal Opens", "Rare", "1.13%"},
        {"World", "Swamp Hut", "Rare", "1.80%"},
        {"Ground", "Open Book", "Rare", "1.80%"},
        {"Underside", "Dripping Pipes", "Uncommon", "5.41%"},
        {"Sky", "Clear Blue", "Common", "9.01%"},
        {"Orbit", "Ringed Planet", "Uncommon", "3.15%"},
        {"Hour", "Noon", "Common", "19.82%"},
        {"Weather", "Light Rain", "Common", "9.01%"},
        {"Palette", "Risograph", "Rare", "2.25%"},
        {"Finish", "Crisp", "Common", "33.78%"},
        {"Era", "1984 Mall", "Uncommon", "5.41%"},
        {"Camera", "Slow Turn", "Common", "40.99%"},
        {"Landmark", "None", "Common", "32.66%"},
        {"Flora", "None", "Common", "9.01%"},
        {"Water", "None", "Common", "38.74%"},
        {"Machine", "Steam Pipes", "Rare", "2.70%"},
        {"Cargo", "Plain Crates", "Common", "24.10%"},
        {"Home", "Hex Carpet", "Epic", "0.68%"},
        {"Relic", "Amulet", "Rare", "1.13%"},
        {"Vehicle", "None", "Common", "42.79%"},
        {"Sign", "INSERT COIN", "Rare", "1.80%"},
        {"Resident", "Blue Cat", "Rare", "1.35%"},
        {"Skin", "Plain", "Common", "37.84%"},
        {"Headwear", "Crown", "Rare", "2.25%"},
        {"Eyes", "Glowing", "Rare", "1.80%"},
        {"Companion", "None", "Common", "41.22%"},
        {"Light", "Moonbeam", "Rare", "1.80%"},
        {"Drift", "Sparks", "Uncommon", "3.15%"},
        {"Motion", "Flicker", "Uncommon", "6.76%"},
        {"Anomaly", "None", "Common", "79.73%"},
        {"Crown", "Flag", "Common", "14.64%"}
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

  @doc "Every scene, in number order."
  def all, do: @scenes

  @doc ~s(The scene an address numbers, such as "1"; any other answers the site's 404.)
  def fetch!(number) do
    Enum.find(@scenes, &(Integer.to_string(&1.number) == number)) || raise NotFoundError
  end

  @doc "The traits shown as tags under a scene: World, Ground, Resident, Landmark and Hour."
  def headline(scene), do: for(category <- @headline, do: trait(scene, category))

  defp trait(scene, category), do: Enum.find(scene.traits, &(&1.category == category))

  @doc """
  A scene's baked file, on this site. It reads only the scene's `name`, so it serves
  the Splats page's factory and island as well as the numbered scenes.
  """
  def file(scene), do: Endpoint.static_path("/splats/#{scene.name}.bin")

  @doc """
  A scene's picture on this site: a still for a stage, `:wide` or `:square`, or one at
  its stage's own size, `:card` or `:item`. Like `file/1`, it reads only the `name`.
  """
  def still(scene, shape), do: Endpoint.static_path(still_path(scene, shape))

  @doc """
  A scene's picture at its full public address: a still, `:wide` or `:square`, or one
  at its stage's own size, `:card` (1440 by 960) or `:item` (1080 by 1080). It names
  the file itself, not this release's fingerprinted copy, so an address kept elsewhere
  still works after the next release.
  """
  def still_url(scene, shape), do: PublicDocuments.url(still_path(scene, shape))

  defp still_path(scene, shape) when shape in [:wide, :square, :card, :item],
    do: "/images/animations/splats-#{scene.name}-#{shape}.png"

  @doc "A scene's own page: the scene alone, at its full public address."
  def page_url(scene), do: PublicDocuments.url(~p"/scenes/#{scene.number}")

  @doc """
  A scene's trait file: its title and line, its item picture (1080 by 1080), its own
  page, the Scenes page, and every trait as a `trait_type` and `value`, in the data's
  order. Every address is the site's full public one.
  """
  def metadata(scene) do
    %{
      name: scene.title,
      description: scene.description,
      image: still_url(scene, :item),
      animation_url: page_url(scene),
      external_url: PublicDocuments.url(~p"/animations/scenes"),
      attributes: for(t <- scene.traits, do: %{trait_type: t.category, value: t.trait})
    }
  end
end
