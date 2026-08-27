defmodule ChurchBands.Swaps.SwapNotifier do
  @moduledoc """
  Envio dos e-mails da troca de escala (US 4.2).

  **Nenhum deles leva token**, e é a diferença para `Accounts.InviteNotifier` e
  `Accounts.PasswordResetNotifier`: aqueles falam com quem **não tem conta**, e
  o token é o que substitui o login. Aqui quem recebe é integrante — o link leva
  à tela e o login é exigido normalmente.

  Em desenvolvimento o adapter local do Swoosh guarda as mensagens em memória —
  elas podem ser lidas em `/dev/mailbox`.
  """
  use ChurchBandsWeb, :verified_routes

  import Swoosh.Email

  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Mailer
  alias ChurchBands.Swaps.SwapRequest

  @doc """
  Avisa o alvo de que alguém pediu troca com ele.

  O corpo diz **quem** pediu, **qual função** está em jogo, **qual dia** o
  solicitante não pode e **qual dia dele** entra no lugar — as quatro coisas de
  que a pessoa precisa para decidir sem abrir o sistema.
  """
  def deliver_request(%SwapRequest{} = request) do
    request
    |> base("Pedido de troca de escala")
    |> text_body("""
    Olá, #{target_name(request)}!

    #{requester_name(request)} pediu uma troca de escala com você.

    Função: #{role(request)}
    #{requester_name(request)} não pode: #{event_line(request.requester_event_band)}
    O seu dia em questão: #{event_line(request.target_event_band)}

    Para ver o pedido, acesse:

    #{url(~p"/swaps")}

    Você ainda não precisa responder nada por aqui — o pedido fica na sua lista.
    """)
    |> Mailer.deliver()
  end

  @doc """
  Avisa o alvo de que o pedido foi cancelado por quem o fez.

  Existe porque o alvo foi chamado para agir e o pedido some da lista dele:
  sumir em silêncio faria a pessoa procurar o que não está mais lá.
  """
  def deliver_cancelled(%SwapRequest{} = request) do
    request
    |> base("Pedido de troca cancelado")
    |> text_body("""
    Olá, #{target_name(request)}!

    #{requester_name(request)} cancelou o pedido de troca de escala com você.

    Função: #{role(request)}
    O dia que estava em questão: #{event_line(request.target_event_band)}

    Não é preciso fazer nada. Se quiser conferir seus pedidos, acesse:

    #{url(~p"/swaps")}
    """)
    |> Mailer.deliver()
  end

  defp base(%SwapRequest{} = request, subject) do
    new()
    |> to(request.target_member.user.email)
    |> from({"Grupo de Louvor", "nao-responda@churchbands.local"})
    |> subject(subject)
  end

  defp requester_name(request), do: request.requester_member.user.name
  defp target_name(request), do: request.target_member.user.name

  # A função é a mesma dos dois lados — é o que `same_role?/2` garante —, então
  # escrevê-la uma vez, do lado de quem pediu, não é escolher um dos dois.
  defp role(request), do: BandMember.role_label(request.requester_member)

  defp event_line(event_band) do
    "#{event_band.event.title} — #{LocalTime.format(event_band.event.starts_at, :short)}" <>
      " (#{event_band.band.name})"
  end
end
