defmodule ChurchBandsWeb.Router do
  use ChurchBandsWeb, :router

  import ChurchBandsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChurchBandsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ChurchBandsWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Telas de acesso total: Pastor e Líder de Louvor.
  scope "/admin", ChurchBandsWeb do
    pipe_through :browser

    live_session :require_full_access,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/invites", InviteLive.Index, :index
      live "/invites/new", InviteLive.Index, :new
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ChurchBandsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:church_bands, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChurchBandsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Atalho de login só para desenvolvimento, para conseguir demonstrar as
    # telas autenticadas antes da tela de login real (US 1.2).
    scope "/dev", ChurchBandsWeb do
      pipe_through :browser

      get "/login", DevSessionController, :index
      get "/login/:user_id", DevSessionController, :create
    end
  end
end
