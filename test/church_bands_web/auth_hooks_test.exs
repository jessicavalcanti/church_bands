defmodule ChurchBandsWeb.AuthHooksTest do
  @moduledoc """
  O sino em tempo real (#112): `AuthHooks.mount_current_user/2` assina o
  tópico de notificações de quem está logado e recarrega `@unread_notifications`
  sozinho, em **qualquer** LiveView — e não só nas telas que também têm
  reatividade própria (`SwapLive.Index`, `NotificationLive.Index`).

  Por isso o teste usa `/bands`, uma tela sem nada a ver com notificações: é
  o jeito de provar que o hook funciona para todo mundo, e não só para quem
  o chamou de propósito.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Notifications
  alias ChurchBands.Realtime

  setup %{conn: conn} do
    user = member_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "o sino" do
    test "acende sozinho quando chega notificação, sem precisar de F5", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/bands")

      refute html =~ ~s(id="unread-notifications")

      {:ok, _notification} =
        Notifications.notify(user, :swap_requested, %{
          title: "Pedido de troca de escala",
          body: "Alguém pediu troca com você.",
          path: "/swaps"
        })

      assert has_element?(view, "#unread-notifications", "1")
    end

    test "ignora mensagem de um tópico que não é o dela, sem derrubar a view", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/bands")

      Phoenix.PubSub.broadcast(
        ChurchBands.PubSub,
        Realtime.notifications_topic(user),
        :uma_mensagem_que_ninguem_conhece
      )

      # Continua viva e do jeito que estava — a mensagem desconhecida caiu no
      # `{:cont, socket}` do hook e não achou `handle_info/2` nenhum depois.
      refute has_element?(view, "#unread-notifications")
      assert render(view) =~ "Bandas"
    end
  end
end
