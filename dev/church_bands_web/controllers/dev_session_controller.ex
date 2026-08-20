defmodule ChurchBandsWeb.DevSessionController do
  @moduledoc """
  Login de atalho, disponível **apenas em desenvolvimento** (a rota está dentro
  do bloco `dev_routes` do router).

  Existe para permitir demonstrar as telas autenticadas enquanto a tela de
  login de verdade não é implementada (US 1.2). Quando a US 1.2 entrar, este
  módulo e suas rotas devem ser removidos.
  """
  use ChurchBandsWeb, :controller

  import Ecto.Query

  alias ChurchBands.Accounts.User
  alias ChurchBands.Repo
  alias ChurchBandsWeb.UserAuth

  def index(conn, _params) do
    users = Repo.all(from u in User, order_by: [asc: u.name])
    render(conn, :index, users: users)
  end

  def create(conn, %{"user_id" => user_id}) do
    case Repo.get(User, user_id) do
      nil ->
        conn
        |> put_flash(:error, "Usuário não encontrado.")
        |> redirect(to: ~p"/dev/login")

      user ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Você entrou como #{user.name}.")
        |> redirect(to: ~p"/admin/invites")
    end
  end
end
