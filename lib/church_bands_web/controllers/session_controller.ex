defmodule ChurchBandsWeb.SessionController do
  @moduledoc """
  Entrada e saída da sessão (US 1.2).

  O formulário de `ChurchBandsWeb.SessionLive` faz POST aqui porque gravar o
  cookie de sessão exige uma requisição HTTP comum, fora da LiveView.
  """
  use ChurchBandsWeb, :controller

  alias ChurchBands.Accounts
  alias ChurchBands.RateLimit
  alias ChurchBandsWeb.UserAuth

  @too_many_attempts "Muitas tentativas seguidas. Aguarde um minuto e tente de novo."

  # O formulário manda texto nos dois campos; requisição fabricada que mande
  # outra coisa não casa com a ação e para em 400, antes de virar chave de
  # contagem ou de busca.
  def create(conn, %{"user" => %{"email" => email, "password" => password}})
      when is_binary(email) and is_binary(password) do
    # A contagem vem antes de conferir a senha, e não depois: é justamente a
    # tentativa recusada que se quer limitar. O e-mail entra normalizado para
    # que trocar uma letra de caixa não abra um contador novo.
    case RateLimit.hit(:login, ip: conn.remote_ip, email: Accounts.normalize_email(email)) do
      :ok -> log_in(conn, email, password)
      {:error, :rate_limited} -> refuse(conn, email, @too_many_attempts)
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, "Você saiu do sistema.")
    |> redirect(to: ~p"/login")
  end

  defp log_in(conn, email, password) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Bem-vindo(a), #{user.name}!")
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
        refuse(conn, email, "E-mail ou senha incorretos.")
    end
  end

  # A recusa devolve ao login com o e-mail preenchido, seja ela por credencial
  # errada ou por excesso de tentativas.
  defp refuse(conn, email, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login?#{[email: email]}")
  end
end
