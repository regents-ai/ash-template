defmodule AshTemplateWeb.ParticlesLabLive do
  @moduledoc """
  Particles: one cloud of fine grains that becomes a control, a Lucide icon or a
  brand mark (`AshTemplateWeb.Components.ParticleField`).

  With no shape chosen the stage plays a loop: the switch turns on, the grains
  fly into a ring that fills, then into a slider whose knob slides across, then
  back to the switch (the `ParticleLab` hook). `?shape=` names one shape from the
  grid below and holds the stage on it. Every control shape sits over its real
  control, which the visitor presses, drags or works with the keys to move the
  grains; a ring, a bar, steps and icons take an Amount slider too.

  Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.ParticleField
  alias AshTemplateWeb.PublicDocuments
  alias Regent.Primitives, as: P

  # The reference film's sequence, which the stage plays when no shape is chosen.
  @loop ~w(switch ring slider)
  @icons ~w(check x triangle-alert info hourglass plus arrow-right search bell lock key wallet copy heart star chart-column activity)
  @groups [
    {"Controls", ~w(switch ring slider bar checkbox radio spinner steps:5)},
    {"Icons", Enum.map(@icons, &"icon:#{&1}")},
    {"Marks", ~w(mark:regents mark:techtree mark:autolaunch)}
  ]
  @shapes Map.new(Enum.flat_map(@groups, &elem(&1, 1)), &{&1, true})
  @radio ~w(Small Medium Large)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(PublicDocuments.page(~p"/animations/particles")) |> assign(groups: @groups)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    shape = chosen(params["shape"])

    {:noreply,
     assign(socket, shape: shape, current: shape || hd(@loop), stage: (shape && [shape]) || @loop)}
  end

  # Only a shape from the grid holds the stage; anything else in the address,
  # a list or a map included, leaves the loop playing.
  defp chosen(shape) when is_map_key(@shapes, shape), do: shape
  defp chosen(_shape), do: nil

  defp start("switch"), do: 0.0
  defp start("ring"), do: 0.6
  defp start("slider"), do: 0.5
  defp start("bar"), do: 0.4
  defp start("checkbox"), do: 1.0
  defp start("radio"), do: 0.0
  defp start("spinner"), do: 0.0
  defp start("steps:5"), do: 0.4
  defp start("icon:" <> _name), do: 1.0
  defp start("mark:" <> _name), do: 0.0

  # The Amount slider and the progress it fills count in whole steps for steps, in hundredths otherwise.
  defp most("steps:5"), do: 5
  defp most(_shape), do: 100

  defp amount(shape), do: round(start(shape) * most(shape))

  defp drive?(shape), do: shape in ~w(ring bar steps:5) or String.starts_with?(shape, "icon:")

  defp name("steps:5"), do: "Steps"
  defp name("icon:" <> icon), do: icon |> String.replace("-", " ") |> String.capitalize()
  defp name("mark:" <> mark), do: String.capitalize(mark)
  defp name(control), do: String.capitalize(control)

  defp shape_path(shape), do: ~p"/animations/particles?#{[shape: shape]}"

  @impl true
  def render(assigns) do
    ~H"""
    <main id="particles-lab" class="motion-lab motion-lab--particles">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Particles
        </p>
        <h1>Particles</h1>
        <p class="motion-lab__lede">
          Fine grains that become a control, an icon or a mark. Press the switch or drag the slider and the grains follow.
        </p>
      </header>

      <section
        id="particle-lab"
        class="particle-lab"
        phx-hook="ParticleLab"
        data-loop={if @shape, do: "off", else: "on"}
        aria-label="Stage"
      >
        <div class="particle-lab__stage">
          <ParticleField.particle_field id="particle-field" shape={@current} value={start(@current)}>
            <.control :for={shape <- @stage} shape={shape} hidden={shape != @current} />
          </ParticleField.particle_field>
        </div>
        <div class="particle-lab__bar">
          <P.button :if={!@shape} variant="secondary" arrow={false} data-particle-play>Pause</P.button>
          <.link
            :if={@shape}
            patch={~p"/animations/particles"}
            class="rg-button rg-button--secondary rg-button--no-arrow"
          >
            <span class="rg-button__label">Loop</span>
          </.link>
          <label
            :for={shape <- @stage}
            :if={drive?(shape)}
            class="particle-lab__amount"
            data-particle-for={shape}
            hidden={shape != @current}
          >
            <span>Amount</span>
            <input
              type="range"
              min="0"
              max={most(shape)}
              step="1"
              value={amount(shape)}
              data-particle-drive
            />
          </label>
        </div>
      </section>

      <section class="particle-lab__shapes" aria-labelledby="particle-shapes-title">
        <h2 id="particle-shapes-title">Shapes</h2>
        <div :for={{group, shapes} <- @groups} class="particle-lab__group">
          <h3>{group}</h3>
          <nav class="flair-tabs" aria-label={group}>
            <.link
              :for={shape <- shapes}
              patch={shape_path(shape)}
              aria-current={shape == @shape && "page"}
            >
              {name(shape)}
            </.link>
          </nav>
        </div>
      </section>
    </main>
    """
  end

  attr :shape, :string, required: true
  attr :hidden, :boolean, required: true

  defp control(%{shape: "switch"} = assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked="false"
      aria-label="Switch"
      class="particle-control particle-control--switch"
      data-particle-for={@shape}
      hidden={@hidden}
    >
      <span class="particle-control__knob"></span>
    </button>
    """
  end

  defp control(%{shape: "slider"} = assigns) do
    ~H"""
    <input
      type="range"
      min="0"
      max="100"
      step="1"
      value={amount(@shape)}
      aria-label="Level"
      class="particle-control particle-control--range"
      data-particle-for={@shape}
      hidden={@hidden}
    />
    """
  end

  defp control(%{shape: "checkbox"} = assigns) do
    ~H"""
    <input
      type="checkbox"
      checked={start(@shape) == 1.0}
      aria-label="Done"
      class="particle-control particle-control--checkbox"
      data-particle-for={@shape}
      hidden={@hidden}
    />
    """
  end

  defp control(%{shape: "radio"} = assigns) do
    assigns = assign(assigns, :options, Enum.with_index(@radio))

    ~H"""
    <fieldset
      class="particle-control particle-control--radio"
      data-particle-for={@shape}
      hidden={@hidden}
    >
      <legend class="visually-hidden">Size</legend>
      <label :for={{option, index} <- @options} class="particle-control__option">
        <input type="radio" name="particle-size" value={option} checked={index == 0} />
        <span class="visually-hidden">{option}</span>
      </label>
    </fieldset>
    """
  end

  defp control(%{shape: "spinner"} = assigns) do
    ~H"""
    <progress
      aria-label="Loading"
      class="particle-control particle-control--progress"
      data-particle-for={@shape}
      hidden={@hidden}
    ></progress>
    """
  end

  defp control(%{shape: shape} = assigns) when shape in ~w(ring bar steps:5) do
    ~H"""
    <progress
      max={most(@shape)}
      value={amount(@shape)}
      aria-label={if @shape == "steps:5", do: "Steps", else: "Progress"}
      class="particle-control particle-control--progress"
      data-particle-for={@shape}
      hidden={@hidden}
    ></progress>
    """
  end

  # An icon or a mark is the field's own drawing; it has no control.
  defp control(assigns), do: ~H""
end
