defmodule ChurchBandsWeb.PageController do
  use ChurchBandsWeb, :controller

  alias ChurchBands.Schedule
  alias ChurchBands.Swaps

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
  """
  def home(conn, _params) do
    upcoming =
      case conn.assigns.current_user do
        nil -> []
        user -> upcoming_for(user)
      end

    render(conn, :home, upcoming_events: upcoming)
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
