defmodule AshTemplateWeb.RouteCatalog do
  @moduledoc "The route specs the shell renders, and the design handoff built from them."

  alias __MODULE__.RouteTarget

  # The site's own first room, which the migration that made the rooms table wrote.
  @first_room "/rooms/general"

  # The rail's sections, in order. Each page belongs to one; its sidebar holds
  # the section's own list and its tabs the section's views.
  @sections [
    %{id: :home, label: "Home", path: "/app", icon: :home},
    %{id: :notes, label: "Notes", path: "/notes", icon: :notes},
    %{id: :rooms, label: "Rooms", path: @first_room, icon: :rooms},
    %{id: :dms, label: "Messages", path: "/dms", icon: :dms},
    %{id: :polls, label: "Polls", path: "/polls", icon: :polls},
    %{id: :chat, label: "Chat", path: "/chat", icon: :chat},
    %{id: :design, label: "Design", path: "/design", icon: :design},
    %{id: :settings, label: "Account", path: "/account", icon: :settings}
  ]

  @sidebars %{
    home: %{
      id: :home,
      title: "Shortcuts",
      targets: [
        %RouteTarget{route_id: :notes, label: "Write a note", path: "/notes"},
        %RouteTarget{route_id: :chat, label: "Start a chat", path: "/chat"},
        %RouteTarget{route_id: :room, label: "General room", path: @first_room},
        %RouteTarget{
          route_id: :connections,
          label: "Connect an account",
          path: "/account/connections"
        }
      ]
    },
    notes: %{id: :notes, title: "Your notes", targets: []},
    # The rooms are rows; the rooms page puts them in the sidebar itself.
    rooms: %{id: :rooms, title: "Rooms", targets: []},
    # The conversations are rows; the messages page puts them in the sidebar itself.
    dms: %{id: :dms, title: "Your messages", targets: []},
    # The polls are rows; the polls page puts them in the sidebar itself.
    polls: %{id: :polls, title: "Polls", targets: []},
    chat: %{id: :chat, title: "Your chats", targets: []},
    design: %{
      id: :design,
      title: "Design",
      targets: [
        %RouteTarget{route_id: :showcase, label: "Components", path: "/showcase"},
        %RouteTarget{route_id: :motion_lab, label: "Motion lab", path: "/animations"},
        %RouteTarget{route_id: :world_cube, label: "World cube", path: "/animations/cube"},
        %RouteTarget{route_id: :twin_cube, label: "Twin cubes", path: "/animations/twin-cube"},
        %RouteTarget{route_id: :foil_cards, label: "Foil cards", path: "/animations/foil"},
        %RouteTarget{route_id: :site_buttons, label: "Site buttons", path: "/animations/buttons"},
        %RouteTarget{route_id: :crown, label: "Crown", path: "/animations/crown"},
        %RouteTarget{
          route_id: :keyfleet_home,
          label: "Keyfleet home",
          path: "/animations/keyfleet"
        },
        %RouteTarget{
          route_id: :header_footer,
          label: "Navigation",
          path: "/animations/header-footer"
        },
        %RouteTarget{route_id: :harbour, label: "Agent harbour", path: "/animations/harbour"},
        %RouteTarget{route_id: :wonders, label: "Ten wonders", path: "/animations/wonders"},
        %RouteTarget{route_id: :swarm_city, label: "Swarm city", path: "/animations/swarm-city"}
      ]
    },
    settings: %{
      id: :settings,
      title: "Help",
      targets: [
        %RouteTarget{route_id: :agents, label: "Connect agent", path: "/agents"},
        %RouteTarget{route_id: :docs, label: "Documentation", path: "/docs"},
        %RouteTarget{route_id: :contact, label: "Contact", path: "/contact"},
        %RouteTarget{route_id: :privacy, label: "Privacy", path: "/privacy"},
        %RouteTarget{route_id: :terms, label: "Terms", path: "/terms"}
      ]
    }
  }

  @tabs %{
    home: [
      %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
      %RouteTarget{route_id: :activity, label: "Activity", path: "/app/activity"}
    ],
    settings: [
      %RouteTarget{route_id: :account, label: "Account", path: "/account"},
      %RouteTarget{route_id: :points, label: "Points", path: "/account/points"},
      %RouteTarget{route_id: :credits, label: "Credits", path: "/account/credits"},
      %RouteTarget{route_id: :wallets, label: "Wallets", path: "/account/wallets"},
      %RouteTarget{route_id: :connections, label: "Connections", path: "/account/connections"}
    ]
  }

  # The product pages share one shell: rail, header controls and background.
  @product %{
    app_id: :product,
    app_display_label: "Ash Template",
    canonical_root: "/app",
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
      section: nil,
      sidebar_model: %{id: :public, title: nil, targets: []},
      tabs: [],
      header_controls: [],
      background_slot: :home,
      scroll_policy: :top,
      local_state: %{}
    },
    app: {:home, %{route_id: :app, destination: "/app", page_display_label: "Overview"}},
    activity:
      {:home,
       %{route_id: :activity, destination: "/app/activity", page_display_label: "Activity"}},
    notes: {:notes, %{route_id: :notes, destination: "/notes", page_display_label: "Notes"}},
    room: {:rooms, %{route_id: :room, destination: "/rooms/:room", page_display_label: "Rooms"}},
    dms: {:dms, %{route_id: :dms, destination: "/dms", page_display_label: "Messages"}},
    dm:
      {:dms,
       %{route_id: :dms, destination: "/dms/:conversation_id", page_display_label: "Messages"}},
    polls: {:polls, %{route_id: :polls, destination: "/polls", page_display_label: "Polls"}},
    poll:
      {:polls, %{route_id: :polls, destination: "/polls/:poll_id", page_display_label: "Polls"}},
    chat: {:chat, %{route_id: :chat, destination: "/chat", page_display_label: "Chat"}},
    conversation:
      {:chat,
       %{route_id: :chat, destination: "/chat/:conversation_id", page_display_label: "Chat"}},
    design: {:design, %{route_id: :design, destination: "/design", page_display_label: "Design"}},
    account:
      {:settings, %{route_id: :account, destination: "/account", page_display_label: "Account"}},
    points:
      {:settings,
       %{route_id: :points, destination: "/account/points", page_display_label: "Points"}},
    credits:
      {:settings,
       %{route_id: :credits, destination: "/account/credits", page_display_label: "Credits"}},
    wallets:
      {:settings,
       %{route_id: :wallets, destination: "/account/wallets", page_display_label: "Wallets"}},
    connections:
      {:settings,
       %{
         route_id: :connections,
         destination: "/account/connections",
         page_display_label: "Connections"
       }},
    pair:
      {:settings, %{route_id: :pair, destination: "/pair", page_display_label: "Pair New Agent"}}
  ]
  @routes Enum.map(@routes, fn
            {action, {section, page}} ->
              {action,
               @product
               |> Map.merge(page)
               |> Map.merge(%{
                 section: section,
                 sidebar_model: Map.fetch!(@sidebars, section),
                 tabs: Map.get(@tabs, section, [])
               })}

            route ->
              route
          end)

  # What search finds besides the rooms and the person's own notes and room
  # messages: every page, then the things a person most often comes to do.
  @pages [
    %{label: "Overview", path: "/app"},
    %{label: "Activity", path: "/app/activity"},
    %{label: "Notes", path: "/notes"},
    %{label: "Rooms", path: @first_room},
    %{label: "Messages", path: "/dms"},
    %{label: "Polls", path: "/polls"},
    %{label: "Chat", path: "/chat"},
    %{label: "Account", path: "/account"},
    %{label: "Credits history", path: "/account/credits"},
    %{label: "Wallets", path: "/account/wallets"},
    %{label: "Connections", path: "/account/connections"},
    %{label: "Connect agent", path: "/agents"},
    %{label: "Documentation", path: "/docs"},
    %{label: "Changelog", path: "/changelog"},
    %{label: "Privacy Policy", path: "/privacy"},
    %{label: "Terms of Use", path: "/terms"}
  ]

  @actions [
    %{label: "Write a note", path: "/notes"},
    %{label: "Start a chat", path: "/chat"},
    %{label: "Post in a room", path: @first_room},
    %{label: "Start a poll", path: "/polls"},
    %{label: "Connect an account", path: "/account/connections"},
    %{label: "Connect agent", path: "/agents"},
    %{label: "Copy your wallet address", path: "/account/wallets"}
  ]

  @live_destinations for {_action, %{app_id: :product} = route} <- @routes,
                         do: String.split(route.destination, "/")

  @doc """
  The rail's sections, in order. Design is there while the design pages are
  (`AshTemplateWeb.Showcase.linked?/0`).
  """
  def sections do
    if AshTemplateWeb.Showcase.linked?(),
      do: @sections,
      else: Enum.reject(@sections, &(&1.id == :design))
  end

  @doc "The design pages the Design section lists, in order."
  def design_pages, do: @sidebars.design.targets

  @doc "The pages and actions search offers, as `{group, [%{label, path}]}`."
  def search_entries, do: [{"Pages", @pages}, {"Actions", @actions}]

  @doc "Whether a path opens inside the app, so moving there keeps the shell."
  def live_path?(path) do
    segments = String.split(path, "/")
    Enum.any?(@live_destinations, &same_shape?(&1, segments))
  end

  @doc "Whether a sidebar or tab target opens inside the app."
  def live?(%RouteTarget{path: path}), do: live_path?(path)

  @doc """
  The spec of a live action; a room's or conversation's destination is the one
  its `params` name.
  """
  def fetch!(:room, %{"room" => room}), do: %{fetch!(:room) | destination: "/rooms/#{room}"}

  def fetch!(:conversation, %{"conversation_id" => id}),
    do: %{fetch!(:conversation) | destination: "/chat/#{id}"}

  def fetch!(:dm, %{"conversation_id" => id}), do: %{fetch!(:dm) | destination: "/dms/#{id}"}
  def fetch!(:poll, %{"poll_id" => id}), do: %{fetch!(:poll) | destination: "/polls/#{id}"}

  def fetch!(action, _params), do: fetch!(action)

  @doc "The spec of a live action as the catalog holds it."
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
      title: spec.sidebar_model.title,
      targets: Enum.map(spec.sidebar_model.targets, &handoff_target/1)
    }

    Map.merge(spec, %{
      tabs: Enum.map(spec.tabs, &handoff_target/1),
      live_action: action,
      path_pattern: spec.destination,
      parameter_schema: parameter_schema(action),
      reserved_values: %{},
      sidebar_model: sidebar
    })
  end

  # "/rooms/:room" has the shape of "/rooms/general".
  defp same_shape?(pattern, segments) when length(pattern) == length(segments) do
    pattern
    |> Enum.zip(segments)
    |> Enum.all?(fn
      {":" <> _parameter, _segment} -> true
      {same, same} -> true
      _different -> false
    end)
  end

  defp same_shape?(_pattern, _segments), do: false

  defp parameter_schema(:room),
    do: %{room: %{type: "string", pattern: "^[a-z0-9]+(-[a-z0-9]+)*$", maxLength: 40}}

  defp parameter_schema(action) when action in [:conversation, :dm],
    do: %{conversation_id: %{type: "string", format: "uuid"}}

  defp parameter_schema(:poll), do: %{poll_id: %{type: "string", format: "uuid"}}

  defp parameter_schema(_action), do: %{}

  defp handoff_target(%RouteTarget{} = target) do
    %{
      type: if(live?(target), do: "route", else: "document"),
      route_id: target.route_id,
      label: target.label,
      destination: target.path
    }
  end

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
