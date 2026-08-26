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
    plug ChurchBandsWeb.ContentSecurityPolicy
    plug ChurchBandsWeb.SidebarState
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

    # Catálogo de instrumentos (US 2.8): quem cura o catálogo é quem tem acesso
    # total — o Líder de Banda escolhe dele no formulário de integrante, mas não
    # o alimenta. Por isso a tela inteira nasce restrita e não abre depois: o
    # que a leitura ampla precisa do instrumento é o nome dele na função de
    # quem toca, e isso já aparece no elenco.
    #
    # `/instruments/new` vem **antes** de `/instruments/:id/edit` pela mesma
    # razão de `/bands/new`: o router casa na ordem em que as rotas são
    # declaradas.
    live_session :require_full_access_instruments,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/instruments", InstrumentLive.Index, :index
      live "/instruments/new", InstrumentLive.Index, :new
      live "/instruments/:id/edit", InstrumentLive.Index, :edit
    end

    # Tipos de evento (US 3.1): o vocabulário do calendário é curado por quem
    # tem acesso total, e esta tela **não** abre para leitura ampla depois — o
    # que o resto do sistema precisa do tipo é o nome dele, e esse aparece no
    # evento. Por isso nasce restrita e assim fica.
    #
    # `/event-types/new` vem **antes** de `/event-types/:id/edit` pela mesma
    # razão de `/bands/new`: o router casa na ordem em que as rotas são
    # declaradas.
    live_session :require_full_access_event_types,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/event-types", EventTypeLive.Index, :index
      live "/event-types/new", EventTypeLive.Index, :new
      live "/event-types/:id/edit", EventTypeLive.Index, :edit
    end

    # Escrever no calendário deixou de ser só de acesso total na US 3.4: o Líder
    # de Banda marca o ensaio da banda dele, e passa a editá-lo e cancelá-lo
    # enquanto ela continuar escalada. São **duas `live_session`s**, e não uma,
    # porque as duas rotas passaram a fazer perguntas diferentes — uma
    # `live_session` tem uma lista de `on_mount` só:
    #
    #   * `/events/new` pergunta se a pessoa pode marcar **algum** evento; o
    #     filtro fino, por tipo, é do formulário e do contexto
    #   * `/events/:id/edit` pergunta pelo evento daquele id, e o carrega
    #
    # `/events/new` vem **antes** de `/events/:id` pela mesma razão de
    # `/bands/new`: o router casa na ordem em que as rotas são declaradas, e na
    # ordem inversa "new" seria lido como o id de um evento. As rotas ficaram
    # em `live_session`s diferentes, e é por isso que estes blocos continuam
    # **acima** do de leitura ampla — a ordem que vale é a do arquivo, não a do
    # bloco.
    live_session :require_event_creator,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_event_creator}] do
      live "/events/new", EventLive.Form, :new
    end

    live_session :require_event_manager,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_event_manager}] do
      live "/events/:id/edit", EventLive.Form, :edit
    end

    # O set de uma banda escalada. Nasceu restrito na US 3.6 — só quem montava
    # entrava — e **abriu na US 3.7**, pelo mesmo motivo do catálogo e do
    # repertório: quem toca precisa saber o que vai tocar, e quem não toca tem
    # interesse legítimo. Montar continua sendo de quem monta, e é a própria
    # tela que reconfere `Schedule.manage_set?/2` em cada escrita.
    #
    # Continua numa `live_session` própria, e não na de leitura ampla logo
    # abaixo, porque a rota tem **dois** ids a resolver antes do mount: o
    # evento precisa existir e a banda precisa estar escalada nele, e as duas
    # recusas devolvem para lugares diferentes. Uma `live_session` tem uma
    # lista de `on_mount` só, e é por isso que `:ensure_event_band` não podia
    # entrar na de baixo.
    live_session :require_event_band,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_event_band}] do
      live "/events/:id/bands/:band_id/set", EventSetLive.Show, :show
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

      # Catálogo de músicas (US 2.5): a leitura abre para qualquer um logado —
      # achar a cifra de uma música não podia depender de quem a cadastrou. O
      # cadastro e a edição continuam de acesso total, na `live_session`
      # abaixo, e a exclusão reconfere a permissão no servidor.
      live "/songs", SongLive.Index, :index

      # Repertório da banda (US 2.6): a leitura abre pelo mesmo motivo do
      # catálogo — quem toca precisa chegar à cifra no tom certo antes do
      # ensaio, sem depender de quem monta a lista. Nasceu restrita na US 2.2 e
      # veio para cá; montar o repertório continua atrás do hook próprio,
      # na `live_session` lá embaixo.
      #
      # A banda deixa de vir carregada pelo hook nesta rota, e por isso é o
      # `mount/3` da tela que a busca e devolve <q>Banda não encontrada.</q>.
      live "/bands/:id/repertoire", BandRepertoireLive.Show, :show

      # Calendário e evento (US 3.3): a leitura abre pelo mesmo motivo do
      # catálogo e do repertório — quem toca precisa saber o que a igreja tem
      # marcado, e onde precisa estar, sem depender de quem escreve a agenda.
      # As duas nasceram restritas na US 3.2 e vieram para cá; marcar, editar,
      # cancelar e excluir continuam de acesso total, e `EventLive.Show`
      # reconfere cada uma no servidor.
      live "/calendar", CalendarLive.Index, :index
      live "/events/:id", EventLive.Show, :show
    end

    live_session :require_user_manager,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_user_manager}] do
      live "/users/:id/edit", UserLive.Form, :edit
    end

    # Escrever no catálogo (US 2.1) segue sendo de Pastor e Líder de Louvor,
    # mesmo depois de a US 2.5 ter aberto a leitura de `/songs` logo acima.
    # Esconder o botão nunca foi autorização: quem forçar estas URLs é recusado
    # aqui, antes do mount.
    #
    # `/songs/new` vem **antes** de qualquer rota `/songs/:id`, pela mesma
    # razão de `/bands/new`.
    live_session :require_full_access_songs,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/songs/new", SongLive.Form, :new
      live "/songs/:id/edit", SongLive.Form, :edit
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

    # Montar o repertório da banda (US 2.2) segue sendo de quem responde por
    # ela, mesmo depois de a US 2.6 ter aberto a leitura de
    # `/bands/:id/repertoire` logo acima. Esconder o botão *Adicionar música* na
    # tela nunca foi autorização: quem forçar esta URL é recusado aqui, antes do
    # mount.
    live_session :require_band_repertoire_manager,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_band_repertoire_manager}] do
      live "/bands/:id/repertoire/new", BandRepertoireLive.Form, :new
    end
  end

  # Telas de acesso total: Pastor e Líder de Louvor.
  scope "/admin", ChurchBandsWeb do
    pipe_through :browser

    live_session :require_full_access,
      on_mount: [{ChurchBandsWeb.AuthHooks, :ensure_full_access}] do
      live "/invites", InviteLive.Index, :index
      live "/invites/new", InviteLive.Index, :new

      # Tags temáticas das músicas (US 2.7). Mora aqui, e não junto de
      # `/songs`, porque é a única tela do catálogo que **nunca** abre para
      # leitura ampla: quando a US 2.5 liberar a leitura das músicas, as tags
      # continuarão visíveis nelas e o cadastro continuará sendo daqui.
      live "/tags", TagLive.Index, :index
      live "/tags/new", TagLive.Index, :new
      live "/tags/:id/edit", TagLive.Index, :edit
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

      # As duas ferramentas escrevem script e estilo direto na página e as duas
      # sabem assinar o que escrevem, desde que se diga onde está o nonce da
      # requisição — que aqui é sempre `conn.assigns.csp_nonce`
      # (`ChurchBandsWeb.ContentSecurityPolicy`). Sem isso a CSP as bloquearia,
      # e `/dev/mailbox` é onde o roteiro de testes vai ler os e-mails.
      live_dashboard "/dashboard",
        metrics: ChurchBandsWeb.Telemetry,
        csp_nonce_assign_key: %{img: :csp_nonce, style: :csp_nonce, script: :csp_nonce}

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end
  end
end
