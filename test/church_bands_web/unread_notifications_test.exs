defmodule ChurchBandsWeb.UnreadNotificationsTest do
  @moduledoc """
  O plug que leva o número do sino às telas de controller (US 4.5).

  O efeito visível — o contador no cabeçalho da home — é exercido em
  `ChurchBandsWeb.PageControllerTest`. O que só aparece olhando o plug de perto
  é o **visitante**: a vitrine pública de `/` passa por ele em toda visita, e
  quem não entrou não pode custar consulta nenhuma.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.NotificationsFixtures

  alias ChurchBandsWeb.UnreadNotifications

  defp run(conn, current_user) do
    conn
    |> Plug.Conn.assign(:current_user, current_user)
    |> UnreadNotifications.call(UnreadNotifications.init([]))
  end

  test "conta as não lidas de quem está logado", %{conn: conn} do
    user = member_fixture()
    notification_fixture(user)
    notification_fixture(user)
    notification_fixture(user, read_at: ChurchBands.LocalTime.now())

    assert run(conn, user).assigns.unread_notifications == 2
  end

  test "quem leu tudo chega com zero", %{conn: conn} do
    assert run(conn, member_fixture()).assigns.unread_notifications == 0
  end

  test "visitante chega com zero", %{conn: conn} do
    assert run(conn, nil).assigns.unread_notifications == 0
  end
end
