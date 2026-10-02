defmodule AshTemplateWeb.RouteCatalog do
  @moduledoc "The route specs the shell renders, and the design handoff built from them."

  alias __MODULE__.RouteTarget

  # The product pages share one shell: sidebar, header controls and background.
  @product %{
    app_id: :product,
    app_display_label: "Ash Template",
    canonical_root: "/app",
    sidebar_model: %{
      id: :product,
      targets: [
        %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
        %RouteTarget{route_id: :notes, label: "Notes", path: "/notes"},
        %RouteTarget{route_id: :account, label: "Account", path: "/account"}
      ]
    },
    header_controls: [:profile_actions],
    background_slot: :product,
    scroll_policy: :top,
    local_state: %{}
  }

  @routes [
    home: %{
      route_id: :home,
      destination: "/",
      app_id: nil,
      app_display_label: nil,
      page_display_label: "Ash Template",
      canonical_root: "/",
      sidebar_model: %{id: :public, targets: []},
      header_controls: [],
      background_slot: :home,
      scroll_policy: :top,
      local_state: %{}
    },
    app:
      Map.merge(@product, %{route_id: :app, destination: "/app", page_display_label: "Overview"}),
    notes:
      Map.merge(@product, %{route_id: :notes, destination: "/notes", page_display_label: "Notes"}),
    account:
      Map.merge(@product, %{
        route_id: :account,
        destination: "/account",
        page_display_label: "Account"
      })
  ]

  @doc "The spec of a live action. No route takes parameters, so `params` is not read."
  def fetch!(action), do: Keyword.fetch!(@routes, action)

  @doc "The catalog as `mix ash_template.route_handoff` writes it, with its sha256 digest."
  def design_handoff do
    handoff = %{"schema_version" => 1, "routes" => Enum.map(@routes, &handoff_route/1)}
    json = handoff |> ordered() |> Jason.encode!()
    %{json: json, digest: Base.encode16(:crypto.hash(:sha256, json), case: :lower)}
  end

  defp handoff_route({action, spec}) do
    sidebar = %{
      id: spec.sidebar_model.id,
      targets: Enum.map(spec.sidebar_model.targets, &handoff_target/1)
    }

    Map.merge(spec, %{
      live_action: action,
      path_pattern: spec.destination,
      parameter_schema: %{},
      reserved_values: %{},
      sidebar_model: sidebar
    })
  end

  defp handoff_target(%RouteTarget{} = target),
    do: %{type: "route", route_id: target.route_id, label: target.label, destination: target.path}

  # Keys sorted at every level, so the digest names the content alone.
  defp ordered(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), ordered(nested)} end)
    |> Enum.sort()
    |> Jason.OrderedObject.new()
  end

  defp ordered(value) when is_list(value), do: Enum.map(value, &ordered/1)
  defp ordered(value), do: value
end
