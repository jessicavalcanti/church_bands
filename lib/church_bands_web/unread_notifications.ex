defmodule ChurchBandsWeb.UnreadNotifications do
  @moduledoc """
  Põe em `conn.assigns` o número de notificações não lidas de quem está
  logado (US 4.5).

  O sino da moldura aparece em **toda** tela do portal, e o portal é desenhado
  por dois caminhos: as LiveViews recebem os assigns de
  `ChurchBandsWeb.AuthHooks`, e as telas de controller recebem dos plugs do
  pipeline `:browser`. Este plug é o segundo caminho — o par de
  `ChurchBandsWeb.SidebarState`, e pelo mesmo motivo: o valor precisa chegar
  aos dois lugares, e cada um tem a sua porta.

  **Os dois assigns têm o mesmo nome**, `:unread_notifications`, e é o que faz
  a home passar `unread={@unread_notifications}` para `Layouts.app/1` como
  qualquer LiveView faria.

  **Ele vem depois de `:fetch_current_user`**, e não antes: o que ele lê é
  `conn.assigns.current_user`, e sem o plug anterior não haveria ninguém de
  quem contar. Visitante custa zero consulta — quem responde por isso é
  `ChurchBands.Notifications.unread_count/1`, que devolve `0` para `nil` sem ir
  ao banco.
  """
  @behaviour Plug

  import Plug.Conn

  alias ChurchBands.Notifications

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    assign(conn, :unread_notifications, Notifications.unread_count(conn.assigns.current_user))
  end
end
