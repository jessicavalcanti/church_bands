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

  # Nenhuma rota passa por aqui ainda: o `scope "/api"` lá embaixo segue
  # comentado, à espera da API REST. Sem rota que o atravesse não há como
  # exercitar o pipeline, então ele fica fora da contagem de cobertura — e
  # volta a contar no dia em que o scope for descomentado.
  # coveralls-ignore-start
  pipeline :api do
    plug :accepts, ["json"]
  end

  # coveralls-ignore-stop

  # Telas públicas: home, login e ativação de conta pelo link do convite.
  scope "/", ChurchBandsWeb do
    pipe_through :browser

    get "/", PageController, :home

    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    live_session :public,
      on_mount: [{ChurchBandsWeb.AuthHooks, :mount_current_user}] do
      live "/login", SessionLive, :new
      live "/invites/:token/activate", InviteLive.Activate, :new

      # Recuperação de senha (US 1.7): quem esqueceu a senha não consegue
      # logar, então as duas telas precisam ser públicas.
      live "/password/forgot", PasswordResetLive.Request, :new
      live "/password/reset/:token", PasswordResetLive.Reset, :edit
    end
  end

  # Telas de qualquer usuário logado — leitura ampla.
  scope "/", ChurchBandsWeb do
    pipe_through :browser

    # Criar banda é exclusivo de Pastor e Líder de Louvor; editar é liberado
    # também ao próprio Líder da Banda, por isso as duas rotas do formulário
    # ficam em `live_session`s diferentes.
    #
    # `/bands/new` precisa vir **antes** de `/bands/:id`: o router casa na
    # ordem em que as rotas são declaradas, e na ordem inversa "new" seria
    # lido como o id de uma banda.
    live_session :require_full_access_bands,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/bands/new", BandLive.Form, :new
    end

    live_session :require_authenticated,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_authenticated}] do
      live "/bands", BandLive.Index, :index
      live "/bands/:id", BandLive.Show, :show

      # Perfil não recebe id: cada um edita o próprio, e o alvo é sempre o
      # `current_user` do socket.
      live "/profile", ProfileLive, :edit

      # Lista de pessoas (US 1.8): leitura ampla, como a de bandas. A edição
      # dos dados de outra pessoa fica logo abaixo, com permissão própria.
      live "/users", UserLive.Index, :index
    end

    live_session :require_user_manager,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_user_manager}] do
      live "/users/:id/edit", UserLive.Form, :edit
    end

    live_session :require_band_editor,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_band_editor}] do
      live "/bands/:id/edit", BandLive.Form, :edit
    end

    # Integrantes da banda (US 1.4): mesmo grupo de pessoas da edição, mas com
    # permissão própria — quem responde pela banda cuida de quem toca nela.
    live_session :require_band_member_manager,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_band_member_manager}] do
      live "/bands/:id/members/new", MemberLive.Form, :new

      # Corrigir a função de quem já está no elenco (DT-9): mesma permissão de
      # adicionar, porque é a mesma pergunta — quem responde por esta banda.
      live "/bands/:id/members/:member_id/edit", MemberLive.Form, :edit
    end
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
  end
end
