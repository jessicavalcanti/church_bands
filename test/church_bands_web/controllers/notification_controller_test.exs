defmodule ChurchBandsWeb.NotificationControllerTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.NotificationsFixtures

  alias ChurchBands.Notifications

  describe "open/2" do
    test "marca como lida e leva ao caminho da notificação", %{conn: conn} do
      user = member_fixture()
      aviso = notification_fixture(user, path: "/swaps?from=notification")

      conn = conn |> log_in_user(user) |> post(~p"/notifications/#{aviso.id}/open")

      assert redirected_to(conn) == "/swaps?from=notification"
      assert [lida] = Notifications.list_for_user(user)
      refute is_nil(lida.read_at)
    end

    # Abrir de novo o que já estava lido não é erro nenhum: o clique repetido
    # leva ao mesmo lugar, e a hora da primeira leitura não se reescreve.
    test "abrir a já lida leva ao mesmo lugar, e não muda a hora da leitura", %{conn: conn} do
      user = member_fixture()
      antes = DateTime.add(ChurchBands.LocalTime.now(), -1, :hour)
      aviso = notification_fixture(user, read_at: antes)

      conn = conn |> log_in_user(user) |> post(~p"/notifications/#{aviso.id}/open")

      assert redirected_to(conn) == aviso.path
      assert [lida] = Notifications.list_for_user(user)
      assert DateTime.compare(lida.read_at, aviso.read_at) == :eq
    end

    # A notificação de outra pessoa e o id que não existe dão na **mesma**
    # recusa: dizer <q>existe, mas não é sua</q> já contaria alguma coisa sobre
    # a vida de terceiros.
    test "a notificação de outra pessoa volta para a home, sem ser marcada", %{conn: conn} do
      dona = member_fixture()
      intrusa = member_fixture()
      aviso = notification_fixture(dona)

      conn = conn |> log_in_user(intrusa) |> post(~p"/notifications/#{aviso.id}/open")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Notificação não encontrada."

      assert [intacta] = Notifications.list_for_user(dona)
      assert is_nil(intacta.read_at)
    end

    test "o id que não existe recebe a mesma recusa", %{conn: conn} do
      conn = conn |> log_in_user(member_fixture()) |> post(~p"/notifications/0/open")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Notificação não encontrada."
    end

    test "o id que nem é um id recebe a mesma recusa", %{conn: conn} do
      conn = conn |> log_in_user(member_fixture()) |> post(~p"/notifications/abacaxi/open")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Notificação não encontrada."
    end

    test "quem não está logado é mandado para o login", %{conn: conn} do
      user = member_fixture()
      aviso = notification_fixture(user)

      conn = post(conn, ~p"/notifications/#{aviso.id}/open")

      assert redirected_to(conn) == ~p"/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Você precisa entrar para acessar esta página."

      assert [intacta] = Notifications.list_for_user(user)
      assert is_nil(intacta.read_at)
    end
  end
end
