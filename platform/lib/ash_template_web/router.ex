defmodule AshTemplateWeb.Router do
  @moduledoc "Every route, with the pipeline and live session that admit it."
  use AshTemplateWeb, :router
  use ErrorTracker.Web, :router

  alias AshTemplateWeb.{ContentSecurityPolicy, Live.Session, Showcase}

  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug AshTemplateWeb.Plugs.Theme
    plug AshTemplateWeb.Plugs.Panels
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug AshTemplateWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    # These pages can start sign-in.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug AshTemplateWeb.Plugs.LaunchGate
  end

  # API credentials never use cookies; consent uses the verified browser and CSRF pipeline.
  scope "/", AshTemplateWeb do
    pipe_through :api
    get "/.well-known/oauth-protected-resource", OAuthController, :resource_metadata
    get "/.well-known/oauth-authorization-server", OAuthController, :server_metadata
    post "/oauth/register", OAuthController, :register, log: false
    post "/oauth/token", OAuthController, :token, log: false
    post "/oauth/revoke", OAuthController, :revoke, log: false
  end

  scope "/oauth", AshTemplateWeb do
    pipe_through :browser
    get "/authorize", OAuthController, :authorize, log: false
    post "/authorize", OAuthController, :approve, log: false
    get "/connections", OAuthController, :connections, log: false
    post "/connections/revoke", OAuthController, :revoke_connection, log: false
  end

  # An agent's request, signed with its wallet; the signature is its only sign-in.
  pipeline :agent_api do
    plug :accepts, ["json"]
    plug AshTemplateWeb.Plugs.LaunchGate
    plug AshTemplateWeb.Plugs.AgentWallet
  end

  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :public_documents do
    plug :accepts, ["html"]
    plug :fetch_session
    plug AshTemplateWeb.Plugs.Theme
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug :protect_from_forgery

    # Reading only: these pages never start sign-in, so they send no referrer.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading(),
      "referrer-policy" => "no-referrer"
    }
  end

  # The saved errors: Credits admins only. Anyone else gets the not-found page under
  # the reading policy; an admin's page replaces it with one carrying this
  # request's nonce (AshTemplateWeb.ErrorsAdmin).
  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :errors_admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.reading(),
      "referrer-policy" => "no-referrer"
    }

    plug AshTemplateWeb.ErrorsAdmin
  end

  def enforce_session_authority(conn, _opts),
    do: AshTemplateWeb.PrivySessionController.enforce_authority(conn)

  # The showcase setting guards every page below (AshTemplateWeb.Showcase).
  pipeline :showcase do
    plug Showcase, :pages
  end

  pipeline :wallet_lab do
    plug Showcase, :lab
  end

  pipeline :motion_lab do
    plug Showcase, :motion_lab
  end

  # The showcase pages are HTML; only the catalog also answers JSON. Each pipeline
  # negotiates its formats first, so a refusal carries no page headers, and sends
  # the headers of a page that can start sign-in.
  @showcase_headers %{"content-security-policy" => ContentSecurityPolicy.sign_in()}

  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :showcase_browser do
    plug :accepts, ["html"]
    plug :showcase_page
    plug :put_secure_browser_headers, @showcase_headers
  end

  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :showcase_catalog do
    plug :accepts, ["html", "json"]
    plug :showcase_page
    plug :put_secure_browser_headers, @showcase_headers
  end

  # The browser pipeline without the launch gate: the showcase is open or absent.
  pipeline :showcase_page do
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug AshTemplateWeb.Plugs.Theme
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug :protect_from_forgery
  end

  # The catalog also frames its own preview, so its policy replaces the one above.
  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  pipeline :framed_preview do
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.showcase()
    }
  end

  scope "/showcase", AshTemplateWeb.Showcase do
    pipe_through [:showcase, :showcase_catalog, :framed_preview]
    get "/catalog", CatalogController, :show
    get "/style.css", CatalogController, :style
  end

  scope "/showcase", AshTemplateWeb do
    pipe_through [:showcase, :showcase_browser, :framed_preview]

    live_session :showcase_catalog,
      session: {Session, :render_context, []},
      on_mount: [{Showcase, :pages}, {Session, :load_human}] do
      live "/", ShowcaseLive, :index
      live "/preview", ShowcaseLive, :preview
    end
  end

  scope "/showcase", AshTemplateWeb do
    pipe_through [:showcase, :showcase_browser]

    live_session :showcase,
      session: {Session, :render_context, []},
      on_mount: [{Showcase, :pages}, {Session, :load_human}] do
      live "/privy", PrivyShowcaseLive, :index
      live "/wallet", WalletShowcaseLive, :index
      live "/payments", PaymentsShowcaseLive, :index
      live "/funds", FundsShowcaseLive, :index
      live "/discussion", DiscussionShowcaseLive, :index
      live "/figures", FiguresShowcaseLive, :index
      live "/grammar", GrammarShowcaseLive, :nouns
      live "/grammar/verbs", GrammarShowcaseLive, :verbs
      live "/grammar/layers", GrammarShowcaseLive, :layers
    end
  end

  scope "/showcase", AshTemplateWeb do
    pipe_through [:wallet_lab, :showcase_browser]

    live_session :wallet_lab,
      session: {Session, :render_context, []},
      on_mount: [{Showcase, :lab}, {Session, :load_human}] do
      live "/onchain", OnchainShowcaseLive, :index
      live "/credits", CreditsShowcaseLive, :index
    end
  end

  scope "/", AshTemplateWeb do
    get "/healthz", HealthController, :show
    get "/openapi.json", PublicPagesController, :openapi
    get "/sitemap.xml", PublicPagesController, :sitemap
    get "/robots.txt", PublicPagesController, :robots
    get "/llms.txt", PublicPagesController, :llms
    get "/agents.md", PublicPagesController, :agents
    get "/skill.md", PublicPagesController, :skill_guide
    get "/agents/:agent/skill.md", PublicPagesController, :agent_skill_guide
    get "/capabilities.json", PublicPagesController, :capabilities
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/indexnow-key.txt", PublicPagesController, :indexnow_key
    get "/.well-known/api-catalog", PublicPagesController, :api_catalog
  end

  # The build skills and the agent guide (AshTemplateWeb.AgentSkills).
  scope "/", AshTemplateWeb do
    pipe_through :showcase
    get "/build/skill.md", PublicPagesController, :build_skill
    get "/.well-known/agent-skills/*path", PublicPagesController, :agent_skill
  end

  scope "/", AshTemplateWeb do
    pipe_through [:showcase, :public_documents]
    get "/skills", PublicPagesController, :skills
  end

  scope "/", AshTemplateWeb do
    pipe_through :public_documents
    get "/docs", PublicPagesController, :show
    get "/about", PublicPagesController, :show
    get "/contact", PublicPagesController, :show
    get "/changelog", PublicPagesController, :show
    get "/agents", PublicPagesController, :show
    get "/agents/:agent", PublicPagesController, :show
  end

  # Stripe's signed notices about card purchases of Credits.
  scope "/api/stripe", AshTemplateWeb do
    pipe_through :api
    post "/notices", StripeController, :notice
  end

  scope "/api/v1", AshTemplateWeb do
    pipe_through :api
    get "/health", HealthController, :status
    get "/about", PublicPagesController, :document, assigns: %{document: "/about"}
    get "/docs", PublicPagesController, :document, assigns: %{document: "/docs"}
    get "/sites/:site/tools", SiteToolsController, :tools
    get "/siwa/help", SiteToolsController, :siwa_help
    get "/notes", NotesController, :index
    post "/notes", NotesController, :create
    get "/notes/:id", NotesController, :show
    patch "/notes/:id", NotesController, :update
    delete "/notes/:id", NotesController, :delete
    get "/rooms", RoomsController, :index
    get "/rooms/:room/messages", RoomsController, :messages
    get "/rooms/:room/messages/:id", RoomsController, :message
    get "/polls", PollsController, :index
    get "/polls/:poll", PollsController, :show
  end

  # The person's own profile, with the Privy proof pair (RegentIdentity.HTTP).
  scope "/api/v1" do
    pipe_through :api
    forward "/profile", RegentIdentity.HTTP, otp_app: :ash_template
  end

  # An agent pairs with the person who gave it a code, and checks in; both are
  # signed, and RegentAgents.HTTP checks each signature itself.
  scope "/api/agents" do
    pipe_through :api
    forward "/v1", RegentAgents.HTTP
  end

  scope "/api/v1" do
    pipe_through :agent_api
    post "/rooms", AshTemplateWeb.RoomsController, :create
    patch "/rooms/:room", AshTemplateWeb.RoomsController, :topic
    post "/rooms/:room/messages", AshTemplateWeb.RoomsController, :post
    patch "/rooms/:room/messages/:id", AshTemplateWeb.RoomsController, :update
    delete "/rooms/:room/messages/:id", AshTemplateWeb.RoomsController, :delete
    post "/rooms/:room/messages/:id/like", AshTemplateWeb.RoomsController, :like
    delete "/rooms/:room/messages/:id/like", AshTemplateWeb.RoomsController, :unlike
    post "/rooms/:room/messages/:id/report", AshTemplateWeb.RoomsController, :report
    post "/polls", AshTemplateWeb.PollsController, :create
    post "/polls/:poll/vote", AshTemplateWeb.PollsController, :vote
    post "/polls/:poll/end", AshTemplateWeb.PollsController, :end_poll
    get "/agents/me", AshTemplateWeb.AgentsController, :profile
    patch "/agents/me", AshTemplateWeb.AgentsController, :edit_profile
  end

  # After /agents/me, so "me" never reads as an agent's id.
  scope "/api/v1", AshTemplateWeb do
    pipe_through :api
    get "/agents/:id", AgentsController, :show
  end

  # What only a paired agent does: search, pins and label ratings on its
  # person's notes, their Credits and Points, reading their activity and marking
  # it read, room search, and mutes.
  scope "/api/v1", AshTemplateWeb do
    pipe_through :api
    post "/rooms/search", PairedAgentController, :search_rooms
    get "/mutes", PairedAgentController, :mutes
    post "/mutes", PairedAgentController, :add_mute
    delete "/mutes/:id", PairedAgentController, :remove_mute
    get "/account/balances", PairedAgentController, :balances
    post "/account/credits/history", PairedAgentController, :credits_history
    get "/account/points", PairedAgentController, :points
    post "/activity", PairedAgentController, :activity
    post "/activity/read", PairedAgentController, :mark_activity_read
    post "/notes/search", PairedAgentController, :search_notes
    get "/notes/:id/pin-price", PairedAgentController, :pin_price
    post "/notes/:id/pin", PairedAgentController, :pin_note
    post "/notes/:id/unpin", PairedAgentController, :unpin_note
    post "/notes/:id/archive", PairedAgentController, :archive_note
    post "/notes/:id/unarchive", PairedAgentController, :unarchive_note
    post "/note-labels/:id/report", PairedAgentController, :report_label
  end

  # A paired agent's direct messages, as its person has them on /dms.
  scope "/api/v1", AshTemplateWeb do
    pipe_through :api
    get "/dms", DmsController, :index
    get "/dms/blocked", DmsController, :blocked
    post "/dms", DmsController, :open
    post "/dms/:conversation/history", DmsController, :history
    post "/dms/:conversation/messages", DmsController, :send_message
    post "/dms/:conversation/block", DmsController, :block
    post "/dms/:conversation/unblock", DmsController, :unblock
  end

  scope "/", AshTemplateWeb do
    pipe_through :browser

    live_session :home, session: {Session, :render_context, []} do
      live "/", HomeLive, :home
    end

    get "/too-many-pages", TooManyPagesController, :show
    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/failure", PrivySessionController, :failure
    post "/visit-log", VisitLogController, :create, log: false
    post "/auth/privy/session", PrivySessionController, :create
    get "/auth/session", PrivySessionController, :show
    delete "/auth/privy/session", PrivySessionController, :delete

    live_session :product_shell,
      session: {Session, :render_context, []},
      on_mount: [AshTemplateWeb.Live.LaunchGateHook, {Session, :load_human}] do
      live "/app", ShellLive, :app
      live "/app/activity", ShellLive, :activity
      live "/notes", ShellLive, :notes
      live "/rooms/:room", ShellLive, :room
      live "/dms", ShellLive, :dms
      live "/dms/:conversation_id", ShellLive, :dm
      live "/polls", ShellLive, :polls
      live "/polls/:poll_id", ShellLive, :poll
      live "/chat", ShellLive, :chat
      live "/chat/:conversation_id", ShellLive, :conversation
      live "/design", ShellLive, :design
      live "/account", ShellLive, :account
      live "/account/points", ShellLive, :points
      live "/account/credits", ShellLive, :credits
      live "/account/wallets", ShellLive, :wallets
      live "/account/connections", ShellLive, :connections
      live "/pair", ShellLive, :pair
    end
  end

  scope "/admin" do
    pipe_through :errors_admin

    error_tracker_dashboard("/errors",
      on_mount: [AshTemplateWeb.ErrorsAdmin],
      csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    )
  end

  # The motion lab: public once the site opens, unless the showcase is off.
  scope "/", AshTemplateWeb do
    pipe_through [:motion_lab, :browser]

    live_session :motion_lab,
      session: {Session, :render_context, []},
      on_mount: [{Showcase, :motion_lab}, AshTemplateWeb.Live.LaunchGateHook] do
      live "/animations", AnimationsLive, :index
      live "/animations/crown", CrownLive, :index
      live "/animations/cube", WorldCubeLive, :index
      live "/animations/foil", FoilCardsLive, :index
      live "/animations/buttons", SiteButtonsLive, :index
      live "/animations/twin-cube", TwinCubeLive, :index
      live "/animations/keyfleet", KeyfleetHeroLive, :index
      live "/animations/header-footer", HeaderFooterLive, :short
      live "/animations/header-footer/long", HeaderFooterLive, :long
      live "/animations/harbour", HarbourLive, :index
      live "/animations/harbour/:place", HarbourLive, :place
      live "/animations/wonders", WondersLive, :index
      live "/animations/swarm-city", SwarmCityLive, :index
      live "/animations/swarm-city/:place", SwarmCityLive, :place
    end
  end
end
