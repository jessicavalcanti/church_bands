defmodule ChurchBandsWeb.PageControllerTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.NotificationsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Schedule

  test "visitante vê o convite para entrar", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Grupo de Louvor"
    assert html =~ "home-login-button"
    refute html =~ "logout-link"
  end

  test "a vitrine abre com a ilustração, e o portal de quem entrou não", %{conn: conn} do
    visitante = conn |> get(~p"/") |> html_response(200)
    logado = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

    assert visitante =~ ~s(id="worship-illustration")
    refute logado =~ ~s(id="worship-illustration")
  end

  test "quem está logado vê o nome e o papel de acesso", %{conn: conn} do
    user = member_fixture(%{name: "Carla Musicista"})
    html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

    assert html =~ "Carla Musicista"
    assert html =~ "Músico(a)"
    assert html =~ "logout-link"
    refute html =~ "home-invites-button"
  end

  test "Líder de Louvor vê o atalho para os convites", %{conn: conn} do
    html = conn |> log_in_user(worship_leader_fixture()) |> get(~p"/") |> html_response(200)

    assert html =~ "home-invites-button"
    assert html =~ "Líder de Louvor"
  end

  # A home é a única tela de controller do portal, e é ela que exercita o
  # caminho do plug `ChurchBandsWeb.UnreadNotifications`. O número tem de ser o
  # mesmo que uma LiveView mostra — os dois assigns têm o mesmo nome de
  # propósito (US 4.5).
  describe "o sino na tela de controller" do
    test "mostra o número de não lidas de quem está logado", %{conn: conn} do
      user = member_fixture()
      notification_fixture(user)
      notification_fixture(user)

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="notifications-bell")
      assert html =~ ~s(id="unread-notifications")
    end

    test "sem não lidas o sino continua lá, e o contador não", %{conn: conn} do
      html = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="notifications-bell")
      refute html =~ ~s(id="unread-notifications")
    end

    test "a home e uma LiveView mostram o mesmo número", %{conn: conn} do
      user = member_fixture()
      notification_fixture(user)
      notification_fixture(user)
      notification_fixture(user)

      conn = log_in_user(conn, user)

      home = conn |> get(~p"/") |> html_response(200)
      {:ok, _view, calendario} = live(conn, ~p"/calendar")

      assert contador(home) == "3"
      assert contador(calendario) == "3"
    end

    defp contador(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#unread-notifications")
      |> LazyHTML.text()
      |> String.trim()
    end
  end

  describe "o bloco Meus próximos eventos" do
    setup do
      carla = member_fixture(%{name: "Carla Musicista"})

      ebenezer =
        band_fixture(%{name: "Banda Ebenezer #{System.unique_integer([:positive])}"})

      band_member_fixture(%{band: ebenezer, user: carla})

      %{carla: carla, ebenezer: ebenezer}
    end

    defp escalar(band, attrs) do
      evento = event_fixture(Map.put(attrs, :starts_at, in_days(3)))
      event_band_fixture(%{event: evento, band: band})
      evento
    end

    test "mostra o culto da banda, com a banda e o link para o evento", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalar(ebenezer, %{title: "Culto da Noite", location: "Templo"})

      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "Meus próximos eventos"
      assert html =~ "upcoming-event-#{culto.id}"
      assert html =~ ~s(href="/events/#{culto.id}")
      assert html =~ "Culto da Noite"
      assert html =~ "Templo"
      assert html =~ ebenezer.name
      refute html =~ "upcoming-events-empty"
    end

    test "o evento cancelado aparece riscado, com o rótulo Cancelado", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalar(ebenezer, %{title: "Culto da Noite", status: :cancelled})

      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-cancelled-#{culto.id}"
      assert html =~ "Cancelado"
      assert html =~ "line-through"
    end

    # O bloco **não some** quando está vazio: uma tela que muda de forma por
    # motivo invisível faz quem olha achar que perdeu alguma coisa.
    test "sem evento nos próximos 30 dias, o bloco mostra a mensagem e o link do calendário", %{
      conn: conn,
      carla: carla
    } do
      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "Meus próximos eventos"
      assert html =~ "Nenhum evento seu nos próximos 30 dias."
      assert html =~ "Ver calendário"
      assert html =~ ~s(href="/calendar")
    end

    test "quem não está em banda nenhuma vê a mesma mensagem", %{
      conn: conn,
      ebenezer: ebenezer
    } do
      escalar(ebenezer, %{title: "Culto da Noite"})

      html = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ "Nenhum evento seu nos próximos 30 dias."
      refute html =~ "Culto da Noite"
    end

    test "o visitante não vê o bloco", %{conn: conn, ebenezer: ebenezer} do
      escalar(ebenezer, %{title: "Culto da Noite"})

      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "Meus próximos eventos"
      refute html =~ "Culto da Noite"
    end

    test "sem troca nenhuma, a linha não ganha marca", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalar(ebenezer, %{title: "Culto da Noite"})

      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      refute html =~ "upcoming-event-swap-#{culto.id}"
      refute html =~ "upcoming-event-provisional-#{culto.id}"
      refute html =~ "Provisório"
    end
  end

  describe "a troca aceita no bloco Meus próximos eventos" do
    setup [:cenario_de_troca]

    test "quem cobriu vê o culto da outra banda, marcado", %{conn: conn} = ctx do
      trocar(ctx, :cover)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-#{ctx.culto_a.id}"
      assert html =~ "upcoming-event-provisional-#{ctx.culto_a.id}"
      assert html =~ "Provisório"
      assert html =~ "no lugar de Elias Guitarrista"
    end

    test "quem foi coberto continua com o dia na lista, marcado", %{conn: conn} = ctx do
      trocar(ctx, :cover)

      html = conn |> log_in_user(ctx.elias) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-#{ctx.culto_a.id}"
      assert html =~ "upcoming-event-swap-#{ctx.culto_a.id}"
      assert html =~ "Rafael Guitarrista vai no seu lugar"
      refute html =~ "upcoming-event-provisional-#{ctx.culto_a.id}"
    end

    test "em trocar o dia, cada um vê as duas linhas marcadas", %{conn: conn} = ctx do
      trocar(ctx, :swap)

      do_rafael = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert do_rafael =~ "upcoming-event-provisional-#{ctx.culto_a.id}"
      assert do_rafael =~ "no lugar de Elias Guitarrista"
      assert do_rafael =~ "upcoming-event-swap-#{ctx.culto_b.id}"
      assert do_rafael =~ "Elias Guitarrista vai no seu lugar"

      do_elias = conn |> log_in_user(ctx.elias) |> get(~p"/") |> html_response(200)

      assert do_elias =~ "upcoming-event-provisional-#{ctx.culto_b.id}"
      assert do_elias =~ "no lugar de Rafael Guitarrista"
      assert do_elias =~ "upcoming-event-swap-#{ctx.culto_a.id}"
      assert do_elias =~ "Rafael Guitarrista vai no seu lugar"
    end

    test "o dia assumido entra na ordem cronológica, e não num bloco à parte",
         %{conn: conn} =
           ctx do
      trocar(ctx, :cover)

      # O ensaio é daqui a 2 dias, o culto assumido a 3 e o culto dele a 4: o
      # assumido tem de cair **no meio**, e não antes nem depois de todos.
      ensaio = event_fixture(%{title: "Ensaio da Banda B", starts_at: in_days(2)})
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert [ensaio.id, ctx.culto_a.id, ctx.culto_b.id] ==
               Enum.sort_by(
                 [ensaio.id, ctx.culto_a.id, ctx.culto_b.id],
                 &posicao(html, "upcoming-event-#{&1}")
               )
    end

    test "o dia assumido fora dos 30 dias não entra", %{conn: conn} = ctx do
      # `backdate/2` grava a data direto, e serve para adiantar como serve para
      # atrasar: o evento precisa nascer perto para a escala existir, e só
      # depois vai para longe.
      backdate(ctx.culto_a, in_days(40))
      trocar(ctx, :cover)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      refute html =~ "upcoming-event-#{ctx.culto_a.id}"
      # O dia dele continua lá: a janela é a mesma para o dia assumido e para
      # o de sempre.
      assert html =~ "upcoming-event-#{ctx.culto_b.id}"
    end

    test "o dia assumido cancelado aparece riscado e marcado", %{conn: conn} = ctx do
      trocar(ctx, :cover)
      {:ok, _} = Schedule.cancel_event(ctx.culto_a)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-cancelled-#{ctx.culto_a.id}"
      assert html =~ "upcoming-event-provisional-#{ctx.culto_a.id}"
      assert html =~ "line-through"
    end

    # A troca é exceção sobre a escala: sem escala não há exceção, e a lista
    # volta sozinha ao que era — não há nada a limpar.
    test "desescalar a banda desfaz as duas marcas", %{conn: conn} = ctx do
      trocar(ctx, :swap)
      {:ok, _} = Schedule.unschedule_band(ctx.escala_a)

      do_rafael = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      refute do_rafael =~ "upcoming-event-#{ctx.culto_a.id}"
      refute do_rafael =~ "upcoming-event-swap-#{ctx.culto_b.id}"
      assert do_rafael =~ "upcoming-event-#{ctx.culto_b.id}"
    end

    test "acesso total vê a agenda inteira, e sem marca nenhuma: a troca não é dele",
         %{
           conn: conn
         } = ctx do
      trocar(ctx, :swap)

      html = conn |> log_in_user(pastor_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-#{ctx.culto_a.id}"
      assert html =~ "upcoming-event-#{ctx.culto_b.id}"
      refute html =~ "Provisório"
      refute html =~ "vai no seu lugar"
    end
  end

  describe "o bloco Trocas pendentes" do
    setup [:cenario_de_troca]

    defp pedir(ctx, attrs \\ %{}) do
      swap_request_fixture(
        Map.merge(
          %{
            requester_event_band: ctx.escala_a,
            requester_member: ctx.elias_a,
            target_event_band: ctx.escala_b,
            target_member: ctx.rafael_b
          },
          attrs
        )
      )
    end

    test "quem recebeu vê quem pediu, a função, os dois dias e o botão de responder",
         %{conn: conn} = ctx do
      pedido = pedir(ctx)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert html =~ "Trocas pendentes"
      assert html =~ "pending-swap-#{pedido.id}"
      assert html =~ "Elias Guitarrista"
      assert html =~ "Guitarra"
      assert html =~ "pending-swap-origin-#{pedido.id}"
      assert html =~ "Culto da Banda A"
      assert html =~ "pending-swap-target-#{pedido.id}"
      assert html =~ "Culto da Banda B"
    end

    test "o botão Responder leva a /swaps, onde os três botões estão",
         %{conn: conn} = ctx do
      pedido = pedir(ctx)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert html =~ "pending-swap-respond-#{pedido.id}"
      assert html =~ ~s(href="/swaps")
    end

    test "quem enviou vê o pedido como espera, com o nome de quem foi procurado",
         %{conn: conn} = ctx do
      pedido = pedir(ctx)

      html = conn |> log_in_user(ctx.elias) |> get(~p"/") |> html_response(200)

      assert html =~ "pending-swap-#{pedido.id}"
      assert html =~ "Esperando resposta de"
      assert html =~ "Rafael Guitarrista"
      # Espera não é ação: a linha do enviado não ganha botão.
      refute html =~ "pending-swap-respond-#{pedido.id}"
    end

    # A diferença entre este bloco e *Meus próximos eventos*: ali o vazio é
    # resposta, e aqui um <q>nenhuma troca pendente</q> permanente seria ruído
    # na tela de todo mundo, todo dia.
    test "sem pedido pendente nenhum o bloco não aparece, nem vazio",
         %{conn: conn} = ctx do
      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      refute html =~ "Trocas pendentes"
      refute html =~ ~s(id="pending-swaps")
    end

    test "o pedido de evento cancelado sai do bloco, e continua em /swaps",
         %{conn: conn} = ctx do
      pedido = pedir(ctx)
      {:ok, _} = Schedule.cancel_event(ctx.culto_a)

      conn = log_in_user(conn, ctx.rafael)
      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "Trocas pendentes"

      {:ok, _view, swaps} = live(conn, ~p"/swaps")
      assert swaps =~ "received-request-#{pedido.id}"
    end

    test "o pedido respondido sai do bloco", %{conn: conn} = ctx do
      pedido = pedir(ctx)

      {:ok, _} =
        ChurchBands.Swaps.decline_request(ctx.rafael, ChurchBands.Swaps.get_request(pedido.id))

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      refute html =~ "Trocas pendentes"
    end

    # O que espera resposta vem antes do que é só informação: a home é lida de
    # cima para baixo.
    test "o bloco aparece antes de Meus próximos eventos", %{conn: conn} = ctx do
      pedir(ctx)

      html = conn |> log_in_user(ctx.rafael) |> get(~p"/") |> html_response(200)

      assert posicao(html, "Trocas pendentes") < posicao(html, "Meus próximos eventos")
    end

    test "acesso total não vê os pedidos dos outros", %{conn: conn} = ctx do
      pedir(ctx)

      html = conn |> log_in_user(pastor_fixture()) |> get(~p"/") |> html_response(200)

      refute html =~ "Trocas pendentes"
    end

    test "o visitante não vê o bloco", %{conn: conn} = ctx do
      pedir(ctx)

      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "Trocas pendentes"
    end
  end

  describe "o bloco Últimas notificações" do
    test "mostra as cinco mais recentes, com as não lidas destacadas", %{conn: conn} do
      user = member_fixture()
      agora = ChurchBands.LocalTime.now()

      avisos =
        for hora <- 0..6 do
          notification_fixture(user,
            title: "Aviso #{hora}",
            inserted_at: DateTime.add(agora, -hora, :hour)
          )
        end

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ "Últimas notificações"

      {mostradas, escondidas} = Enum.split(avisos, 5)

      for aviso <- mostradas, do: assert(html =~ "recent-notification-#{aviso.id}")
      for aviso <- escondidas, do: refute(html =~ "recent-notification-#{aviso.id}")

      assert html =~ "notification-unread-#{hd(avisos).id}"
      assert html =~ "Não lida"
    end

    test "a já lida aparece sem o destaque", %{conn: conn} do
      user = member_fixture()
      lida = notification_fixture(user, read_at: ChurchBands.LocalTime.now())

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ "recent-notification-#{lida.id}"
      refute html =~ "notification-unread-#{lida.id}"
      refute html =~ "Não lida"
    end

    test "Ver todas leva à central", %{conn: conn} do
      user = member_fixture()
      notification_fixture(user)

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="recent-notifications-all")
      assert html =~ ~s(href="/notifications")
    end

    test "cada linha aponta para a porta que marca como lida", %{conn: conn} do
      user = member_fixture()
      aviso = notification_fixture(user)

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(href="/notifications/#{aviso.id}/open")
      assert html =~ ~s(data-method="post")
    end

    test "sem notificação nenhuma o bloco não aparece", %{conn: conn} do
      html = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

      refute html =~ "Últimas notificações"
      refute html =~ ~s(id="recent-notifications")
    end

    test "acesso total não vê as notificações dos outros", %{conn: conn} do
      notification_fixture(member_fixture(), title: "Aviso de outra pessoa")

      html = conn |> log_in_user(pastor_fixture()) |> get(~p"/") |> html_response(200)

      refute html =~ "Últimas notificações"
      refute html =~ "Aviso de outra pessoa"
    end

    test "o visitante não vê o bloco", %{conn: conn} do
      notification_fixture(member_fixture())

      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "Últimas notificações"
    end
  end

  # O cenário da troca, igual ao da suíte do contexto: o Elias toca guitarra na
  # Banda A, que tem um culto; o Rafael toca guitarra na Banda B, que tem
  # outro. Os dois eventos nascem juntos para a ordem da lista ser previsível.
  defp cenario_de_troca(_contexto) do
    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = banda("Banda A")
    banda_b = banda("Banda B")

    culto_a = event_fixture(%{title: "Culto da Banda A", starts_at: in_days(3)})
    culto_b = event_fixture(%{title: "Culto da Banda B", starts_at: in_days(4)})

    %{
      elias: elias,
      rafael: rafael,
      banda_a: banda_a,
      banda_b: banda_b,
      culto_a: culto_a,
      culto_b: culto_b,
      elias_a: band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"}),
      rafael_b: band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"}),
      escala_a: event_band_fixture(%{event: culto_a, band: banda_a}),
      escala_b: event_band_fixture(%{event: culto_b, band: banda_b})
    }
  end

  # A troca já aceita, gravada direto no repositório: a tela é o assunto aqui,
  # e passar por `accept_request/3` traria a elegibilidade junto.
  defp trocar(ctx, mode) do
    swap_request_fixture(%{
      requester_event_band: ctx.escala_a,
      requester_member: ctx.elias_a,
      target_event_band: ctx.escala_b,
      target_member: ctx.rafael_b,
      status: :accepted,
      mode: mode
    })
  end

  defp banda(nome), do: band_fixture(%{name: "#{nome} #{System.unique_integer([:positive])}"})

  defp posicao(html, trecho) do
    [posicao] = :binary.match(html, trecho) |> Tuple.to_list() |> Enum.take(1)
    posicao
  end
end
