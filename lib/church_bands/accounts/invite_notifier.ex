defmodule ChurchBands.Accounts.InviteNotifier do
  @moduledoc """
  Envio dos e-mails de convite.

  Em desenvolvimento o adapter local do Swoosh guarda as mensagens em memória —
  elas podem ser lidas em `/dev/mailbox`.
  """
  use ChurchBandsWeb, :verified_routes

  import Swoosh.Email

  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Mailer

  @doc """
  Envia o convite com o link de ativação da conta.
  """
  def deliver_invite(%Invite{} = invite) do
    url = activation_url(invite)

    new()
    |> to(invite.email)
    |> from({"Grupo de Louvor", "nao-responda@churchbands.local"})
    |> subject("Seu convite para o Grupo de Louvor")
    |> text_body("""
    Olá!

    Você foi convidado(a) para fazer parte do Grupo de Louvor.

    Para criar sua conta, acesse o link abaixo:

    #{url}

    O convite é válido por #{Invite.validity_in_days()} dias.

    Se você não esperava este convite, basta ignorar esta mensagem.
    """)
    |> Mailer.deliver()
  end

  @doc """
  URL de ativação da conta a partir do token do convite.
  """
  def activation_url(%Invite{token: token}) do
    url(~p"/invites/#{token}/activate")
  end
end
