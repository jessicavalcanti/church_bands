defmodule ChurchBandsWeb.PageController do
  use ChurchBandsWeb, :controller

  alias ChurchBands.Schedule

  @doc """
  A tela inicial, nos dois estados que ela tem: a vitrine pública de quem ainda
  não entrou e o portal de quem já está dentro.

  Desde a US 3.5 o ramo logado carrega **Meus próximos eventos**, e é aqui que
  eles vêm — a tela inicial é um controller, e não uma LiveView, então não há
  `mount/3` para buscá-los. O visitante não paga a consulta: sem usuário não há
  agenda de ninguém para montar.
  """
  def home(conn, _params) do
    upcoming =
      case conn.assigns.current_user do
        nil -> []
        user -> Schedule.list_upcoming_events_for_user(user)
      end

    render(conn, :home, upcoming_events: upcoming)
  end
end
