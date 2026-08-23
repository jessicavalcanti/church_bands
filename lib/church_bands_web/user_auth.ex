defmodule ChurchBandsWeb.UserAuth do
  @moduledoc """
  Plugs de sessão: carrega o usuário logado e exige autenticação/autorização
  nas requisições HTTP.

  A tela de login vive em `ChurchBandsWeb.SessionLive` e o POST que de fato
  abre a sessão, em `ChurchBandsWeb.SessionController`.
  """
  use ChurchBandsWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User

  @doc """
  Grava o usuário na sessão, renovando-a para evitar fixação de sessão.

  Junto do id vai a impressão digital da senha
  (`Accounts.session_fingerprint/1`): é ela que faz a sessão morrer quando a
  senha muda — ver `session_user/1`.
  """
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_session(:auth_fingerprint, Accounts.session_fingerprint(user))
    |> put_session(:live_socket_id, live_socket_id(user))
  end

  @doc """
  Encerra a sessão do usuário. Quem chama decide para onde redirecionar.
  """
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      ChurchBandsWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    renew_session(conn)
  end

  @doc """
  Derruba **todas** as sessões vivas de `user`, em qualquer navegador.

  O tópico do socket é o mesmo para todas as sessões da pessoa
  (`users_sessions:<id>`), então um broadcast só alcança o computador de casa
  e o do trabalho. Quem recebe o `"disconnect"` recarrega a página, e aí a
  sessão é conferida de novo do zero.

  Usada na redefinição de senha: a troca já invalida os cookies antigos por
  dentro (`session_user/1`), e o broadcast é o que faz isso valer **agora**
  numa aba que estava aberta, em vez de só na próxima requisição dela.
  """
  def disconnect_sessions(%User{} = user) do
    ChurchBandsWeb.Endpoint.broadcast(live_socket_id(user), "disconnect", %{})
  end

  @doc """
  Carrega o usuário da sessão em `conn.assigns.current_user`.
  """
  def fetch_current_user(conn, _opts) do
    assign(conn, :current_user, session_user(get_session(conn)))
  end

  @doc """
  Usuário dono de `session`, ou `nil` quando ela não vale mais.

  Vale a sessão que tem id **e** a impressão digital da senha que aquele
  usuário tem agora. Redefinir a senha muda o `hashed_password` e, com ele, a
  impressão: todo cookie emitido antes da troca deixa de abrir a conta, esteja
  ele em que navegador estiver.

  As LiveViews leem a sessão por aqui também (`ChurchBandsWeb.AuthHooks`), para
  que a regra seja a mesma nos dois caminhos de entrada.
  """
  def session_user(%{"user_id" => user_id, "auth_fingerprint" => fingerprint}) do
    case Accounts.get_user(user_id) do
      %User{} = user -> if fingerprint == Accounts.session_fingerprint(user), do: user
      nil -> nil
    end
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

  # O tópico que reúne todas as sessões de uma pessoa. Nasce em `log_in_user/2`,
  # dentro da sessão, e é lido de fora dela por `disconnect_sessions/1`.
  defp live_socket_id(%User{id: id}), do: "users_sessions:#{id}"

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
