defmodule ChurchBandsWeb.SessionController do
  @moduledoc """
  Entrada e saída da sessão (US 1.2).

  O formulário de `ChurchBandsWeb.SessionLive` faz POST aqui porque gravar o
  cookie de sessão exige uma requisição HTTP comum, fora da LiveView.
  """
  use ChurchBandsWeb, :controller

  alias ChurchBands.Accounts
  alias ChurchBandsWeb.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Bem-vindo(a), #{user.name}!")
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "E-mail ou senha incorretos.")
        |> redirect(to: ~p"/login?#{[email: email]}")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, "Você saiu do sistema.")
    |> redirect(to: ~p"/login")
  end
end
