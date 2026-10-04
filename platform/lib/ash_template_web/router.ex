defmodule AshTemplateWeb.Router do
  @moduledoc "Every route, with the pipeline and live session that admit it."
  use AshTemplateWeb, :router

  alias AshTemplateWeb.{ContentSecurityPolicy, Live.Session, Showcase}

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug AshTemplateWeb.Plugs.Theme
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug AshTemplateWeb.Plugs.LaunchGate
    plug :protect_from_forgery

    # These pages can start wallet sign-in.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => ContentSecurityPolicy.sign_in()
    }
  end

  # The chat page in `mix ash_ai.gen.chat`'s own look loads its own stylesheet.
  pipeline :ash_ai_chat do
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :ash_ai_chat}
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug AshTemplateWeb.Plugs.LaunchGate
  end

  # An agent's request, signed with its wallet; the signature is its only sign-in.
  pipeline :agent_api do
    plug :accepts, ["json"]
    plug AshTemplateWeb.Plugs.LaunchGate
    plug AshTemplateWeb.Plugs.AgentWallet
  end

  # The browser tools a page offers its own agent: JSON on the page's own
  # session cookie, with the page's CSRF token on every write.
  pipeline :page_tools do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :enforce_session_authority
    plug AshTemplateWeb.Plugs.LaunchGate
    plug :protect_from_forgery
  end

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
  # the headers of a page that can start wallet sign-in.
  @showcase_headers %{"content-security-policy" => ContentSecurityPolicy.sign_in()}

  pipeline :showcase_browser do
    plug :accepts, ["html"]
    plug :showcase_page
    plug :put_secure_browser_headers, @showcase_headers
  end

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
      live "/discussion", DiscussionShowcaseLive, :index
    end
  end

  scope "/showcase", AshTemplateWeb do
    pipe_through [:wallet_lab, :showcase_browser]

    live_session :wallet_lab,
      session: {Session, :render_context, []},
      on_mount: [{Showcase, :lab}, {Session, :load_human}] do
      live "/onchain", OnchainShowcaseLive, :index
    end
  end

  scope "/", AshTemplateWeb do
    get "/healthz", HealthController, :show
    get "/developers", PublicPagesController, :developers
    get "/openapi.json", PublicPagesController, :openapi
    get "/sitemap.xml", PublicPagesController, :sitemap
    get "/robots.txt", PublicPagesController, :robots
    get "/llms.txt", PublicPagesController, :llms
    get "/capabilities", PublicPagesController, :capabilities
    get "/.well-known/security.txt", PublicPagesController, :security
    get "/.well-known/api-catalog", PublicPagesController, :api_catalog
  end

  # The build skills and the agent guide (AshTemplateWeb.AgentSkills).
  scope "/", AshTemplateWeb do
    pipe_through :showcase
    get "/skill.md", PublicPagesController, :skill_guide
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
  end

  scope "/api/v1" do
    pipe_through :api
    get "/health", AshTemplateWeb.HealthController, :status
    forward "/profile", RegentIdentity.HTTP, otp_app: :ash_template
    get "/notes", AshTemplateWeb.NotesController, :index
    post "/notes", AshTemplateWeb.NotesController, :create
    get "/notes/:id", AshTemplateWeb.NotesController, :show
    patch "/notes/:id", AshTemplateWeb.NotesController, :update
    delete "/notes/:id", AshTemplateWeb.NotesController, :delete
    get "/rooms", AshTemplateWeb.RoomsController, :index
    get "/rooms/:room/messages", AshTemplateWeb.RoomsController, :messages
  end

  scope "/api/v1" do
    pipe_through :agent_api
    post "/rooms/:room/messages", AshTemplateWeb.RoomsController, :post
  end

  scope "/tools", AshTemplateWeb do
    pipe_through :page_tools
    get "/notes", PageToolsController, :notes
    post "/notes", PageToolsController, :create_note
    get "/notes/:id", PageToolsController, :note
    get "/rooms/:room/messages", PageToolsController, :room_messages
    post "/rooms/:room/messages", PageToolsController, :post_message
  end

  # Before the product shell, whose `/chat/:conversation_id` would take `original`.
  scope "/chat/original", AshTemplateWeb do
    pipe_through [:browser, :ash_ai_chat]

    live_session :ash_ai_chat,
      session: {Session, :render_context, []},
      on_mount: [AshTemplateWeb.Live.LaunchGateHook, {Session, :load_human}] do
      live "/", ChatOriginalLive, :index
      live "/:conversation_id", ChatOriginalLive, :conversation
    end
  end

  scope "/", AshTemplateWeb do
    pipe_through :browser

    live "/", HomeLive, :home
    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms

    get "/auth/csrf", PrivySessionController, :csrf
    post "/auth/privy/failure", PrivySessionController, :failure
    post "/auth/privy/session", PrivySessionController, :create
    get "/auth/session", PrivySessionController, :show
    delete "/auth/privy/session", PrivySessionController, :delete

    live_session :product_shell,
      session: {Session, :render_context, []},
      on_mount: [AshTemplateWeb.Live.LaunchGateHook, {Session, :load_human}] do
      live "/app", ShellLive, :app
      live "/notes", ShellLive, :notes
      live "/rooms/:room", ShellLive, :room
      live "/chat", ShellLive, :chat
      live "/chat/:conversation_id", ShellLive, :conversation
      live "/account", ShellLive, :account
    end
  end

  # The motion lab: public once the site opens, unless the showcase is off.
  scope "/", AshTemplateWeb do
    pipe_through [:motion_lab, :browser]

    live_session :motion_lab,
      on_mount: [{Showcase, :motion_lab}, AshTemplateWeb.Live.LaunchGateHook] do
      live "/animations", AnimationsLive, :index
    end
  end
end
