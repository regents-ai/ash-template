defmodule AshTemplateWeb.WondersLive do
  @moduledoc """
  Ten wonders: ten pictures drawn live on the visitor's graphics card, each one
  set in motion by Anime.js and steered by the visitor's hand. Every one is a
  canvas island with a still picture the server draws first, kept for a visitor
  who asked for less motion or whose browser cannot draw it. Nothing here reads
  or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias Regent.Primitives, as: P

  # Each wonder: its name in the markup, its title and line, what its picture
  # shows, its first reading, and its buttons as {action, label, extra attributes}.
  @wonders [
    %{
      id: "horizon",
      title: "Event horizon",
      line: "A black hole bending the starlight behind it. Drag it across the sky and let go.",
      picture: "A black hole ringed by a burning disc, the stars around it bent out of place",
      reading: "17 suns",
      buttons: [{"feed", "Feed it", []}]
    },
    %{
      id: "warp",
      title: "Warp drive",
      line: "Hold the button to build to light speed. The pointer steers.",
      picture: "Stars streaming past, stretching into streaks as the ship speeds up",
      reading: "12% of light speed",
      buttons: [{"launch", "Hold to launch", []}]
    },
    %{
      id: "fractal",
      title: "Fractal flight",
      line: "A shape that keeps its detail however close you fly. Drag to turn it.",
      picture: "The Mandelbulb, a glowing shape folded from endless smaller copies of itself",
      reading: "Power 8.0",
      buttons: [{"tour", "Take the tour", []}]
    },
    %{
      id: "tesseract",
      title: "Tesseract",
      line: "A cube with a fourth dimension. Drag to turn it.",
      picture: "A cube inside a cube, their corners joined by glowing edges",
      reading: "0° through the fourth dimension",
      buttons: [{"roll", "Turn it inside out", []}]
    },
    %{
      id: "coral",
      title: "Living coral",
      line: "A pattern that grows by itself. Draw on it with the pointer.",
      picture: "Coral growing across dark water",
      reading: "Coral",
      buttons: [
        {"pattern", "Coral", ["data-pattern": "coral", "aria-pressed": "true"]},
        {"pattern", "Maze", ["data-pattern": "maze", "aria-pressed": "false"]},
        {"pattern", "Cells", ["data-pattern": "cells", "aria-pressed": "false"]},
        {"plant", "Plant again", []}
      ]
    },
    %{
      id: "ink",
      title: "Ink bloom",
      line: "Tap the water to drop ink. Move across it to stir.",
      picture: "Drops of tangerine, blue and green ink spreading through water",
      reading: "Tangerine",
      buttons: [
        {"ink", "Tangerine", ["data-ink": "0", "aria-pressed": "true"]},
        {"ink", "Powder blue", ["data-ink": "1", "aria-pressed": "false"]},
        {"ink", "Green", ["data-ink": "2", "aria-pressed": "false"]}
      ]
    },
    %{
      id: "shatter",
      title: "Glass key",
      line: "Tap the glass to shatter it. Tap again to mend it.",
      picture: "A frosted pane of glass with a key etched in it",
      reading: "Whole",
      buttons: [{"strike", "Strike the glass", []}]
    },
    %{
      id: "aurora",
      title: "Northern lights",
      line: "Curtains of light over a still sea. The pointer is the wind.",
      picture: "Green curtains of light over a dark sea that mirrors them",
      reading: "Calm",
      buttons: [{"storm", "Call a storm", []}]
    },
    %{
      id: "ripples",
      title: "Ripple pool",
      line: "Tap the water. Rings that meet add up and cancel out.",
      picture: "A tiled pool seen through rippling water",
      reading: "0 drops",
      buttons: [{"rain", "Rain", []}]
    },
    %{
      id: "kaleidoscope",
      title: "Kaleidoscope",
      line: "Coloured glass between mirrors. Move across it to shift the glass.",
      picture: "A circle of mirrored coloured glass in tangerine, blue, green and coral",
      reading: "6 mirrors",
      buttons: [{"turn", "Turn it", []}]
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/wonders"))
     |> assign(:wonders, @wonders)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="wonders-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Ten wonders
        </p>
        <h1>Ten wonders</h1>
        <p class="motion-lab__lede">
          Ten pictures drawn live, each one waiting for your hand. Tap, drag or hold to play.
        </p>
      </header>
      <div class="wonders">
        <.wonder :for={wonder <- @wonders} wonder={wonder} />
      </div>
    </main>
    """
  end

  attr :wonder, :map, required: true

  defp wonder(assigns) do
    ~H"""
    <article
      id={"wonder-#{@wonder.id}"}
      class="wonder"
      phx-hook="Wonder"
      phx-mounted={JS.ignore_attributes(["data-wonder-ready"])}
      data-wonder={@wonder.id}
      aria-labelledby={"wonder-#{@wonder.id}-title"}
    >
      <div class="wonder__stage" role="img" aria-label={@wonder.picture} data-wonder-stage>
        <div class={"wonder__still wonder__still--#{@wonder.id}"}></div>
        <canvas
          id={"wonder-#{@wonder.id}-canvas"}
          class="wonder__canvas"
          phx-update="ignore"
          data-wonder-canvas
        ></canvas>
      </div>
      <div class="wonder__copy">
        <h2 id={"wonder-#{@wonder.id}-title"}>{@wonder.title}</h2>
        <p>{@wonder.line}</p>
      </div>
      <div id={"wonder-#{@wonder.id}-play"} class="wonder__play" phx-update="ignore">
        <P.button
          :for={{action, label, extra} <- @wonder.buttons}
          variant="secondary"
          data-wonder-action={action}
          {extra}
        >
          {label}
        </P.button>
        <p id={"wonder-#{@wonder.id}-line"} class="wonder__reading" data-wonder-line>
          {@wonder.reading}
        </p>
      </div>
    </article>
    """
  end
end
