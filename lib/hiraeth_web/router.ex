defmodule HiraethWeb.Router do
  use HiraethWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HiraethWeb.Layouts, :root}
    plug :protect_from_forgery
    # Self-contained-page contract (DESIGN.md): no remote fonts/scripts/styles.
    # style-src 'unsafe-inline' is required for LiveView/Tailwind inline styles;
    # connect-src 'self' covers the same-origin LiveView websocket.
    plug :put_secure_browser_headers,
         %{
           "content-security-policy" =>
             "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'"
         }
  end

  pipeline :ops do
    plug :accepts, ["json"]
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: HiraethWeb.Api.Spec
  end

  scope "/api/v1" do
    pipe_through :api

    get "/openapi.json", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/v1", HiraethWeb.Api.V1 do
    pipe_through :api

    get "/books", CatalogController, :books
    get "/books/:slug", CatalogController, :book
    get "/editions/:slug", CatalogController, :edition
    get "/publishers", CatalogController, :publishers
    get "/publishers/:slug", CatalogController, :publisher
    get "/series", CatalogController, :series
    get "/series/:slug", CatalogController, :series_show
    get "/contributors", CatalogController, :contributors
    get "/contributors/:slug", CatalogController, :contributor
  end

  pipeline :covers do
  end

  scope "/covers/cache" do
    pipe_through :covers

    get "/*path", HiraethWeb.CoverController, :show
  end

  scope "/", HiraethWeb do
    pipe_through :ops

    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
  end

  scope "/", HiraethWeb do
    pipe_through :browser

    get "/ops", OpsController, :index
    get "/admin", AdminController, :index
    get "/admin/candidates", AdminController, :candidates
    get "/admin/candidates/:id", AdminController, :show
    post "/admin/candidates/:id/approve", AdminController, :approve
    post "/admin/candidates/:id/reject", AdminController, :reject
    post "/admin/candidates/:id/ignore", AdminController, :ignore
    post "/admin/candidates/:id/override", AdminController, :override
    get "/sitemap.xml", SitemapController, :sitemap
    get "/robots.txt", SitemapController, :robots
    get "/", CatalogPageController, :home
    live "/browse", BrowseLive, :index
    live "/search", SearchLive, :index
    get "/contributors", CatalogPageController, :contributors
    get "/contributors/:slug", CatalogPageController, :contributor
    get "/publishers", CatalogPageController, :publishers
    get "/publishers/a-strange-object", RedirectController, :publisher_group
    get "/publishers/fum-destampa", RedirectController, :publisher_group
    get "/publishers/la-reunion", RedirectController, :publisher_group
    get "/publishers/phoneme-media", RedirectController, :publisher_group
    get "/publishers/:slug", CatalogPageController, :publisher
    get "/series", CatalogPageController, :series
    get "/series/:slug", CatalogPageController, :series_show
    get "/books/:slug", CatalogPageController, :book
    get "/editions/:slug", CatalogPageController, :edition
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:hiraeth, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HiraethWeb.Telemetry
    end
  end
end
