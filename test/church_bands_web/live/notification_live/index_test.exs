defmodule ChurchBandsWeb.NotificationLive.IndexTest do
  @moduledoc """
  A central de notificações (US 4.5).

  Cada um vê só as suas, e o recorte é a consulta: forçar pelo socket o id de
  uma notificação de outra pessoa e forçar um id inventado dão na **mesma**
  recusa, porque dizer <q>existe, mas não é sua</q> já contaria algo sobre a
  vida de terceiros.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.NotificationsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Notifications
  alias ChurchBands.Repo

  setup %{conn: conn} do
    user = member_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "a lista" do
    test "traz as minhas, da mais recente para a mais antiga", %{conn: conn, user: user} do
      agora = LocalTime.now()

      notification_fixture(user,
        title: "A mais antiga",
        inserted_at: DateTime.add(agora, -2, :hour)
      )

      notification_fixture(user, title: "A mais recente", inserted_at: agora)

      {:ok, _view, html} = live(conn, ~p"/notifications")

      assert :binary.match(html, "A mais recente") < :binary.match(html, "A mais antiga")
    end

    test "a não lida vem destacada, e a lida não", %{conn: conn, user: user} do
      por_ler = notification_fixture(user, title: "Por ler")
      lida = notification_fixture(user, title: "Já lida", read_at: LocalTime.now())

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notification-unread-#{por_ler.id}")
      refute has_element?(view, "#notification-unread-#{lida.id}")
    end

    # A já lida perde o preto do título; a por ler o mantém. O que se confere
    # junto é que **só** isso muda de classe: uma condição escrita pela negativa
    # deixava a palavra `true` cair na lista de classes da não lida.
    test "só a lida ganha a classe que apaga o título, e nada de estranho entra na lista", %{
      conn: conn,
      user: user
    } do
      por_ler = notification_fixture(user, title: "Por ler")
      lida = notification_fixture(user, title: "Já lida", read_at: LocalTime.now())

      {:ok, _view, html} = live(conn, ~p"/notifications")

      refute classes_do_titulo(html, por_ler) =~ "text-muted-foreground"
      refute classes_do_titulo(html, por_ler) =~ "true"
      assert classes_do_titulo(html, lida) =~ "text-muted-foreground"
    end

    defp classes_do_titulo(html, notification) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#notification-#{notification.id} span[class*=\"font-medium\"]")
      |> LazyHTML.attribute("class")
      |> Enum.join(" ")
    end

    test "não mostra as de outra pessoa", %{conn: conn, user: user} do
      notification_fixture(user, title: "Minha notificação")
      notification_fixture(member_fixture(), title: "Notificação alheia")

      {:ok, _view, html} = live(conn, ~p"/notifications")

      assert html =~ "Minha notificação"
      refute html =~ "Notificação alheia"
    end

    # Aqui o vazio é o fim do histórico, e não uma resposta a esconder: quem
    # abriu a lista veio ver se tinha algo.
    test "sem notificação nenhuma, diz que não há nada por aqui", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notifications-empty")
      assert render(view) =~ "Nenhuma notificação por aqui."
      refute has_element?(view, "#notifications")
    end
  end

  describe "abrir uma notificação" do
    test "marca como lida e leva ao caminho dela", %{conn: conn, user: user} do
      notification = notification_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert {:error, {:redirect, %{to: "/swaps?from=notification"}}} =
               view |> element("#notification-#{notification.id}") |> render_click()

      assert Repo.reload!(notification).read_at
    end

    # Regra 14: marcar como lido o que já está lido não muda nada e não é erro.
    test "a que já estava lida leva do mesmo jeito, e a data não se mexe", %{
      conn: conn,
      user: user
    } do
      antes = DateTime.add(LocalTime.now(), -1, :hour)
      notification = notification_fixture(user, read_at: antes)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert {:error, {:redirect, %{to: "/swaps?from=notification"}}} =
               view |> element("#notification-#{notification.id}") |> render_click()

      assert Repo.reload!(notification).read_at == notification.read_at
    end
  end

  describe "marcar todas como lidas" do
    test "zera o contador e o botão some", %{conn: conn, user: user} do
      notification_fixture(user)
      notification_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#unread-notifications")

      html = view |> element("#mark-all-read") |> render_click()

      refute html =~ ~s(id="unread-notifications")
      refute has_element?(view, "#mark-all-read")
      assert Notifications.unread_count(user) == 0
    end

    test "sem não lidas, o botão nem aparece", %{conn: conn, user: user} do
      notification_fixture(user, read_at: LocalTime.now())

      {:ok, view, _html} = live(conn, ~p"/notifications")

      refute has_element?(view, "#mark-all-read")
    end
  end

  # Esconder a notificação alheia da lista nunca foi autorização: o caminho de
  # quem dispara o evento pelo socket é este.
  describe "forçar o id pelo socket" do
    test "o id de outra pessoa é recusado, e nada é marcado", %{conn: conn} do
      alheia = notification_fixture(member_fixture())

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert render_click(view, "open", %{"id" => to_string(alheia.id)}) =~
               "Notificação não encontrada."

      assert is_nil(Repo.reload!(alheia).read_at)
    end

    test "o id inventado recebe a mesma recusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert render_click(view, "open", %{"id" => "999999"}) =~ "Notificação não encontrada."
    end

    test "o id que nem número é recebe a mesma recusa, e não estoura", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert render_click(view, "open", %{"id" => "abc"}) =~ "Notificação não encontrada."
    end
  end

  test "quem não está logado é mandado para o login", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
             live(build_conn(), ~p"/notifications")

    assert flash["error"] =~ "Você precisa entrar"
  end
end
