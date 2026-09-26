defmodule AshTemplateWeb.Router do
  use AshTemplateWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :enforce_session_authority
    plug :fetch_live_flash
    plug AshTemplateWeb.Plugs.Theme
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug AshTemplateWeb.Plugs.LaunchGate
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug AshTemplateWeb.Plugs.LaunchGate
  end

  pipeline :public_documents do
    plug :accepts, ["html"]
    plug :fetch_session
    plug AshTemplateWeb.Plugs.Theme
    plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  def enforce_session_authority(conn, _opts) do
    AshTemplateWeb.PrivySessionController.enforce_authority(conn)
  end

  if Application.compile_env(:ash_template, :local_showcase, false) do
    pipeline :local_showcase do
      plug AshTemplateWeb.Showcase.LocalOnly
      plug :accepts, ["html", "json"]
      plug :fetch_session
      plug :enforce_session_authority
      plug :fetch_live_flash
      plug AshTemplateWeb.Plugs.Theme
      plug :put_root_layout, html: {AshTemplateWeb.Layouts, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    scope "/showcase", AshTemplateWeb do
      pipe_through :local_showcase
      get "/catalog", Showcase.CatalogController, :show
      get "/style.css", Showcase.CatalogController, :style

      live_session :local_showcase,
        session: {AshTemplateWeb.Live.Session, :render_context, []},
        on_mount: [AshTemplateWeb.Showcase.LocalOnly, {AshTemplateWeb.Live.Session, :load_human}] do
        live "/", ShowcaseLive, :index
        live "/preview", ShowcaseLive, :preview
        live "/privy", PrivyShowcaseLive, :index
      end
    end
  end

  scope "/", AshTemplateWeb do
    get "/healthz", HealthController, :show
    get "/metrics", MetricsController, :show
    get "/developers", PublicPagesController, :developers
    get "/openapi.json", PublicPagesController, :openapi
    get "/sitemap.xml", PublicPagesController, :sitemap
    get "/robots.txt", PublicPagesController, :robots
    get "/llms.txt", PublicPagesController, :llms
  end

  scope "/", AshTemplateWeb do
    pipe_through :public_documents
    get "/docs", PublicPagesController, :show
    get "/about", PublicPagesController, :show
    get "/contact", PublicPagesController, :show
  end

  scope "/api/v1" do
    pipe_through :api
    forward "/profile", RegentIdentity.HTTP, otp_app: :ash_template
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
      session: {AshTemplateWeb.Live.Session, :render_context, []},
      on_mount: [AshTemplateWeb.Live.LaunchGateHook, {AshTemplateWeb.Live.Session, :load_human}] do
      live "/app", ShellLive, :app
      live "/account", ShellLive, :account
    end

    # The motion lab: public once the site opens, and linked from nowhere.
    live_session :motion_lab, on_mount: [AshTemplateWeb.Live.LaunchGateHook] do
      live "/animations", AnimationsLive, :index
    end
  end
end
