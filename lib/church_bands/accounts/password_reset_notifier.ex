defmodule ChurchBands.Accounts.PasswordResetNotifier do
  @moduledoc """
  Envio do e-mail de redefinição de senha (US 1.7).

  Em desenvolvimento o adapter local do Swoosh guarda as mensagens em memória —
  elas podem ser lidas em `/dev/mailbox`.
  """
  use ChurchBandsWeb, :verified_routes

  import Swoosh.Email

  alias ChurchBands.Accounts.PasswordResetToken
  alias ChurchBands.Accounts.User
  alias ChurchBands.Mailer

  @doc """
  Envia a `user` o link de redefinição para `token`.

  O token chega aqui em texto claro porque é ele que vai no link; o banco
  guarda só o hash.
  """
  def deliver_reset(%User{} = user, token) when is_binary(token) do
    url = reset_url(token)

    new()
    |> to(user.email)
    |> from({"Grupo de Louvor", "nao-responda@churchbands.local"})
    |> subject("Redefinição de senha do Grupo de Louvor")
    |> text_body("""
    Olá, #{user.name}!

    Recebemos um pedido para redefinir a senha da sua conta.

    Para escolher uma senha nova, acesse o link abaixo:

    #{url}

    O link é válido por #{PasswordResetToken.validity_in_minutes()} minutos e pode ser usado uma única vez.

    Se você não pediu a redefinição, ignore esta mensagem — sua senha atual
    continua valendo.
    """)
    |> Mailer.deliver()
  end

  @doc """
  URL de redefinição de senha a partir do token.
  """
  def reset_url(token) when is_binary(token) do
    url(~p"/password/reset/#{token}")
  end
end
