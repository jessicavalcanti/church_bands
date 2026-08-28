defmodule ChurchBandsWeb.PageController do
  use ChurchBandsWeb, :controller

  alias ChurchBands.Notifications
  alias ChurchBands.Schedule
  alias ChurchBands.Swaps

  # Quantas notificações o resumo da home mostra. É resumo, e não lista: a
  # central inteira continua em `/notifications`, e é para lá que o **Ver
  # todas** aponta.
  @recent_notifications 5

  @doc """
  A tela inicial, nos dois estados que ela tem: a vitrine pública de quem ainda
  não entrou e o portal de quem já está dentro.

  Desde a US 3.5 o ramo logado carrega **Meus próximos eventos**, e é aqui que
  eles vêm — a tela inicial é um controller, e não uma LiveView, então não há
  `mount/3` para buscá-los. O visitante não paga a consulta: sem usuário não há
  agenda de ninguém para montar.

  **A US 4.4 pôs a troca nessa agenda, e a composição é daqui.** `Schedule`
  responde quais são os eventos e `Swaps` diz o que mudou neles; quem conhece
  os dois é a tela, e não um contexto ao outro — é o que mantém a seta da
  US 4.2 apontando para um lado só. São **duas consultas**, e continuam duas
  com qualquer número de trocas: `list_accepted_for_user/1` roda uma vez e
  alimenta as outras duas chamadas, que trabalham em Elixir.

  **A US 4.6 acrescentou mais dois blocos**, e uma consulta cada:
  *Trocas pendentes*, acima da agenda, e *Últimas notificações*, embaixo de
  tudo. A ordem é a da leitura: o que espera resposta sua vem antes do que é
  só informação. Nenhum dos dois cresce em consultas com o número de linhas —
  `Swaps.list_pending_for_user/1` traz os quatro nomes de cada pedido
  pré-carregados, e `Notifications.list_recent/2` corta no banco.
  """
  def home(conn, _params) do
    render(conn, :home, portal_assigns(conn.assigns.current_user))
  end

  # O visitante não paga consulta nenhuma: os três blocos são de quem está
  # logado, e montá-los para quem não os vê seria trabalho para ninguém. As
  # listas vazias existem porque o template é um só — o ramo da vitrine não as
  # lê, mas os assigns precisam estar lá.
  defp portal_assigns(nil) do
    [upcoming_events: [], pending_swaps: %{received: [], sent: []}, recent_notifications: []]
  end

  defp portal_assigns(user) do
    [
      upcoming_events: upcoming_for(user),
      pending_swaps: Swaps.list_pending_for_user(user),
      recent_notifications: Notifications.list_recent(user, @recent_notifications)
    ]
  end

  defp upcoming_for(user) do
    accepted = Swaps.list_accepted_for_user(user)

    user
    |> Schedule.list_upcoming_events_for_user(
      include_event_ids: Swaps.assumed_event_ids(accepted, user)
    )
    |> Swaps.annotate_upcoming(user, accepted)
  end
end
