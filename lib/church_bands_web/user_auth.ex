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

  @doc """
  Grava o usuário na sessão, renovando-a para evitar fixação de sessão.
  """
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
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
  Carrega o usuário da sessão em `conn.assigns.current_user`.
  """
  def fetch_current_user(conn, _opts) do
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        user_id -> Accounts.get_user(user_id)
      end

    assign(conn, :current_user, user)
  end

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

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
