defmodule ChurchBandsWeb.UserAuth do
  @moduledoc """
  Plugs de sessão: carrega o usuário logado e exige autenticação/autorização
  nas requisições HTTP.

  A tela de login vive em `ChurchBandsWeb.SessionLive` e o POST que de fato
  abre a sessão, em `ChurchBandsWeb.SessionController`.

  **A sessão é um token guardado no banco** (DT-12), no formato do
  `phx.gen.auth`: o cookie leva só o token, e quem responde se ele ainda vale é
  `ChurchBands.Accounts.get_user_by_session_token/1`. O desenho anterior punha
  no cookie o id mais uma impressão digital da senha — resolvia a troca de
  senha derrubar tudo, e não resolvia mais nada: sem lista de sessões, não
  havia como fechar uma sem fechar as outras.
  """
  use ChurchBandsWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias ChurchBands.Accounts

  @doc """
  Abre uma sessão para `user`, renovando a anterior para evitar fixação.

  O token nasce aqui e vale por si: não carrega o id nem nada sobre a senha —
  quem sabe de quem ele é, e até quando, é a linha em `users_tokens`.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, live_socket_id(token))
  end

  @doc """
  Encerra a sessão de quem está em `conn`. Quem chama decide para onde
  redirecionar.

  **Fecha uma sessão, não todas**: o token desta some do banco e as outras
  continuam de pé, no navegador em que estiverem.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ChurchBandsWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    renew_session(conn)
  end

  @doc """
  Derruba os sockets das sessões de `tokens`, que já foram apagadas do banco.

  **Cada sessão tem o seu tópico** (`users_sessions:<token>`), então dá para
  derrubar uma sem tocar nas outras — antes o tópico era o mesmo para a pessoa
  inteira, e derrubar era sempre em bloco.

  Usada na redefinição de senha, que apaga todos os tokens da pessoa: o
  broadcast é o que faz a aba aberta em outro navegador cair **agora**, e não
  na próxima requisição dela.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      ChurchBandsWeb.Endpoint.broadcast(live_socket_id(token), "disconnect", %{})
    end)
  end

  @doc """
  Carrega o usuário da sessão em `conn.assigns.current_user`.
  """
  def fetch_current_user(conn, _opts) do
    assign(conn, :current_user, session_user(get_session(conn)))
  end

  @doc """
  Usuário dono de `session`, ou `nil` quando ela não vale mais.

  Vale a sessão cujo token ainda está em `users_tokens` e dentro do prazo. O
  logout apaga o dela; a troca de senha apaga o de todas as sessões da pessoa,
  esteja o cookie em que navegador estiver.

  As LiveViews leem a sessão por aqui também (`ChurchBandsWeb.AuthHooks`), para
  que a regra seja a mesma nos dois caminhos de entrada.
  """
  def session_user(%{"user_token" => token}) do
    Accounts.get_user_by_session_token(token)
  end

  def session_user(_session), do: nil

  @doc """
  Interrompe a requisição quando não há usuário logado.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Você precisa entrar para acessar esta página.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  # O tópico do socket de **uma** sessão. O token é binário e o nome do tópico
  # é texto, daí o encode; e é o token, e não o id do usuário, porque é isso
  # que permite derrubar uma sessão sozinha.
  defp live_socket_id(token) when is_binary(token) do
    "users_sessions:#{Base.url_encode64(token)}"
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
