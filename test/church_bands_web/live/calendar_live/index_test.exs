defmodule ChurchBandsWeb.CalendarLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  # O nome da banda é único no sistema (DT-4) e a suíte roda em paralelo: dois
  # testes criando "Banda Ebenezer" ao mesmo tempo disputam o índice único, e
  # já travaram um no outro. O sufixo mantém o nome legível na asserção e
  # deixa cada teste sozinho com a sua banda.
  defp banda_chamada(nome, attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # Um mês inteiro no futuro, para os eventos poderem ser criados: o fixture
  # recusa data no passado, como a tela. Ele é calculado a partir de hoje, e
  # não fixo no calendário, porque a suíte roda todo dia — um mês escrito à mão
  # viraria passado sozinho.
  defp mes_de_referencia,
    do: LocalTime.today() |> Date.shift(month: 1) |> Date.beginning_of_month()

  defp mes_corrente, do: Date.beginning_of_month(LocalTime.today())

  defp param(%Date{} = mes), do: Calendar.strftime(mes, "%Y-%m")

  defp celula(%Date{} = dia), do: "#day-#{Date.to_iso8601(dia)}"

  # A hora de parede daquele dia convertida no instante que o banco guarda — o
  # mesmo caminho que o formulário percorre.
  defp evento_em(dia, hora, attrs \\ %{}) do
    starts_at = dia |> NaiveDateTime.new!(hora) |> LocalTime.from_local()

    attrs |> Map.new() |> Map.put(:starts_at, starts_at) |> event_fixture()
  end

  describe "quem abre a grade" do
    test "músico comum vê o calendário do mês corrente", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert has_element?(view, "#calendar-grid")

      assert element(view, "#calendar-month") |> render() =~
               LocalTime.format_month(mes_corrente())
    end

    test "músico comum vê os eventos da igreja na grade", %{conn: conn} do
      mes = mes_de_referencia()
      evento = evento_em(Date.add(mes, 9), ~T[19:00:00], %{title: "Culto da Noite"})
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#{celula(Date.add(mes, 9))} #day-event-#{evento.id}")
    end

    test "músico comum não vê o botão de marcar evento", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/calendar")

      refute has_element?(view, "#new-event-button")
    end

    # Desde a US 3.4 quem lidera banda marca o ensaio dela, e por isso vê o
    # botão. Quem não lidera nenhuma continua sem ver.
    test "Líder de Banda abre a grade e marca evento", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, view, _html} = conn |> log_in_user(leader) |> live(~p"/calendar")

      assert has_element?(view, "#calendar-grid")
      assert has_element?(view, "#new-event-button[href='/events/new']")
    end

    test "Pastor vê o botão de marcar evento", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/calendar")

      assert has_element?(view, "#new-event-button[href='/events/new']")
    end

    test "Líder de Louvor vê o botão de marcar evento", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(worship_leader_fixture()) |> live(~p"/calendar")

      assert has_element?(view, "#new-event-button")
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/calendar")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "a grade do mês" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture()), mes: mes_de_referencia()}
    end

    test "o evento aparece na célula do seu dia, com hora e título", %{conn: conn, mes: mes} do
      dia = Date.add(mes, 23)
      evento_em(dia, ~T[19:00:00], %{title: "Culto da Noite"})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      celula = element(view, celula(dia)) |> render()

      assert celula =~ "19:00"
      assert celula =~ "Culto da Noite"
    end

    test "clicar num evento leva ao detalhe dele", %{conn: conn, mes: mes} do
      evento = evento_em(Date.add(mes, 5), ~T[10:00:00])

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#day-event-#{evento.id}[href='/events/#{evento.id}']")
    end

    test "os eventos do dia saem em ordem de hora", %{conn: conn, mes: mes} do
      dia = Date.add(mes, 11)
      noite = evento_em(dia, ~T[19:00:00], %{title: "Noite"})
      manha = evento_em(dia, ~T[09:00:00], %{title: "Manhã"})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      celula = element(view, celula(dia)) |> render()

      assert posicao(celula, "day-event-#{manha.id}") < posicao(celula, "day-event-#{noite.id}")
    end

    # O evento das 23h30 do dia 31 está gravado como dia 1º em UTC. Agrupá-lo
    # pela data crua o jogaria na célula do mês seguinte.
    test "o evento da última noite do mês fica no último dia do mês", %{conn: conn, mes: mes} do
      ultimo = Date.end_of_month(mes)
      evento = evento_em(ultimo, ~T[23:30:00], %{title: "Vigília"})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#{celula(ultimo)} #day-event-#{evento.id}")
    end

    test "o mês sem evento nenhum continua desenhado", %{conn: conn, mes: mes} do
      {:ok, view, html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#calendar-grid")
      assert has_element?(view, celula(mes))
      refute html =~ "day-event-"
    end

    test "hoje aparece destacado", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert has_element?(view, "#{celula(LocalTime.today())} span.bg-primary")
    end

    # A grade vai de domingo a sábado, e as semanas das pontas se completam com
    # os dias do mês vizinho — apagados, porque estão ali para a semana fechar,
    # não para serem lidos como parte deste mês. Setembro de 2026 serve de
    # exemplo fixo porque tem os dois lados: começa numa terça e termina numa
    # quarta. Não precisa de evento nenhum, então também não precisa ser um mês
    # futuro.
    test "os dias do mês vizinho completam a semana, apagados", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=2026-09")

      assert has_element?(view, "#day-2026-08-30.bg-muted\\/30")
      assert has_element?(view, "#day-2026-08-31.bg-muted\\/30")
      refute has_element?(view, "#day-2026-09-01.bg-muted\\/30")
      refute has_element?(view, "#day-2026-09-30.bg-muted\\/30")
      assert has_element?(view, "#day-2026-10-03.bg-muted\\/30")
    end

    # A grade é feita de semanas inteiras: se ela deixasse de fechar em sete, o
    # `grid-cols-7` empurraria os dias para a coluna errada e o mês passaria a
    # mentir sobre em que dia da semana cada coisa cai.
    test "a grade fecha em semanas inteiras, de domingo a sábado", %{conn: conn} do
      for mes <- ["2026-02", "2026-09", "2026-10", "2027-01"] do
        {:ok, _view, html} = live(conn, ~p"/calendar?month=#{mes}")

        dias =
          Regex.scan(~r/id="day-(\d{4}-\d{2}-\d{2})"/, html)
          |> Enum.map(fn [_, dia] -> Date.from_iso8601!(dia) end)

        assert rem(length(dias), 7) == 0
        assert Date.day_of_week(List.first(dias), :sunday) == 1
        assert Date.day_of_week(List.last(dias), :sunday) == 7

        # E são dias consecutivos, sem buraco nem repetição.
        assert dias == Enum.to_list(Date.range(List.first(dias), List.last(dias)))
      end
    end

    test "o evento do dia 1º cai na célula do dia 1º", %{conn: conn, mes: mes} do
      evento = evento_em(mes, ~T[20:00:00], %{title: "Primeiro do mês"})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#{celula(mes)} #day-event-#{evento.id}")
    end
  end

  describe "o dia cheio" do
    setup %{conn: conn} do
      mes = mes_de_referencia()
      dia = Date.add(mes, 14)

      eventos =
        for hora <- [~T[08:00:00], ~T[09:00:00], ~T[10:00:00], ~T[11:00:00], ~T[12:00:00]] do
          evento_em(dia, hora, %{title: "Evento das #{hora.hour}"})
        end

      %{conn: log_in_user(conn, member_fixture()), mes: mes, dia: dia, eventos: eventos}
    end

    test "a célula mostra três e resume o resto em +N", %{conn: conn, mes: mes, dia: dia} = ctx do
      [um, dois, tres, quatro, cinco] = ctx.eventos

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#day-event-#{um.id}")
      assert has_element?(view, "#day-event-#{dois.id}")
      assert has_element?(view, "#day-event-#{tres.id}")
      refute has_element?(view, "#day-event-#{quatro.id}")
      refute has_element?(view, "#day-event-#{cinco.id}")

      assert element(view, "#expand-day-#{Date.to_iso8601(dia)}") |> render() =~ "+2"
    end

    test "expandir a célula mostra os cinco, sem sair da tela", %{conn: conn, mes: mes} = ctx do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      view |> element("#expand-day-#{Date.to_iso8601(ctx.dia)}") |> render_click()

      assert Enum.all?(ctx.eventos, &has_element?(view, "#day-event-#{&1.id}"))
      refute has_element?(view, "#expand-day-#{Date.to_iso8601(ctx.dia)}")
    end

    test "trocar de mês fecha a célula que estava expandida", %{conn: conn, mes: mes} = ctx do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      view |> element("#expand-day-#{Date.to_iso8601(ctx.dia)}") |> render_click()
      view |> element("#next-month") |> render_click()
      view |> element("#previous-month") |> render_click()

      assert has_element?(view, "#expand-day-#{Date.to_iso8601(ctx.dia)}")
    end
  end

  describe "a navegação entre meses" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture())}
    end

    test "o mês seguinte muda a grade e vai para a URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar")

      view |> element("#next-month") |> render_click()

      seguinte = Date.shift(mes_corrente(), month: 1)

      assert assert_patch(view) =~ "month=#{param(seguinte)}"
      assert element(view, "#calendar-month") |> render() =~ LocalTime.format_month(seguinte)
    end

    test "o mês anterior muda a grade e vai para a URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar")

      view |> element("#previous-month") |> render_click()

      anterior = Date.shift(mes_corrente(), month: -1)

      assert assert_patch(view) =~ "month=#{param(anterior)}"
      assert element(view, "#calendar-month") |> render() =~ LocalTime.format_month(anterior)
    end

    test "Hoje volta ao mês corrente depois de navegar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=2027-03")

      assert element(view, "#calendar-month") |> render() =~ "março de 2027"

      view |> element("#current-month") |> render_click()

      assert element(view, "#calendar-month") |> render() =~
               LocalTime.format_month(mes_corrente())
    end

    test "o mês pedido na URL é o que abre", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=2026-09")

      assert element(view, "#calendar-month") |> render() =~ "setembro de 2026"
      assert has_element?(view, "#day-2026-09-01")
    end

    test "mês malformado cai no mês corrente, sem erro", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=banana")

      assert element(view, "#calendar-month") |> render() =~
               LocalTime.format_month(mes_corrente())
    end

    test "mês que não existe no calendário cai no mês corrente", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=2026-13")

      assert element(view, "#calendar-month") |> render() =~
               LocalTime.format_month(mes_corrente())
    end
  end

  describe "o filtro por tipo" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture()), mes: mes_de_referencia()}
    end

    test "filtrar por Ensaio deixa só os ensaios do mês", %{conn: conn, mes: mes} do
      ensaio = evento_em(Date.add(mes, 3), ~T[20:00:00], %{event_type: tipo_chamado("Ensaio")})
      culto = evento_em(Date.add(mes, 6), ~T[19:00:00], %{event_type: tipo_chamado("Culto")})

      {:ok, view, _html} =
        live(conn, ~p"/calendar?month=#{param(mes)}&type=#{tipo_chamado("Ensaio").id}")

      assert has_element?(view, "#day-event-#{ensaio.id}")
      refute has_element?(view, "#day-event-#{culto.id}")
    end

    test "clicar no tipo grava o filtro na URL", %{conn: conn, mes: mes} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      view |> element("#filter-type-#{ensaio.id}") |> render_click()

      assert assert_patch(view) =~ "type=#{ensaio.id}"
    end

    test "o filtro sobrevive à troca de mês", %{conn: conn, mes: mes} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=#{ensaio.id}")

      view |> element("#next-month") |> render_click()

      caminho = assert_patch(view)

      assert caminho =~ "type=#{ensaio.id}"
      assert caminho =~ "month=#{param(Date.shift(mes, month: 1))}"
    end

    test "Todos limpa o filtro", %{conn: conn, mes: mes} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=#{ensaio.id}")

      view |> element("#filter-type-all") |> render_click()

      refute assert_patch(view) =~ "type="
    end

    test "tipo sem evento no mês mostra a mensagem, com a grade desenhada", %{
      conn: conn,
      mes: mes
    } do
      evento_em(Date.add(mes, 6), ~T[19:00:00], %{event_type: tipo_chamado("Culto")})
      vazio = tipo_chamado("Confraternização")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=#{vazio.id}")

      assert render(view) =~ "Nenhum evento neste mês para o filtro escolhido."
      assert has_element?(view, "#calendar-grid")
    end

    # O mês vazio sem filtro não diz nada: a grade desenhada já é a resposta, e
    # a frase fala de um filtro que ninguém escolheu.
    test "o mês vazio sem filtro não mostra a mensagem do filtro", %{conn: conn, mes: mes} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      refute has_element?(view, "#calendar-filtered-empty")
    end

    test "tipo malformado mostra o mês inteiro, sem filtro", %{conn: conn, mes: mes} do
      evento = evento_em(Date.add(mes, 6), ~T[19:00:00])

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=banana")

      assert has_element?(view, "#day-event-#{evento.id}")
      assert has_element?(view, "#filter-type-all[aria-current='true']")
    end

    test "tipo que não existe mostra o mês inteiro, sem filtro", %{conn: conn, mes: mes} do
      evento = evento_em(Date.add(mes, 6), ~T[19:00:00])

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=999999")

      assert has_element?(view, "#day-event-#{evento.id}")
      assert has_element?(view, "#filter-type-all[aria-current='true']")
    end

    test "o tipo escolhido aparece marcado na barra de filtros", %{conn: conn, mes: mes} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&type=#{ensaio.id}")

      assert has_element?(view, "#filter-type-#{ensaio.id}[aria-current='true']")
      refute has_element?(view, "#filter-type-all[aria-current='true']")
    end
  end

  describe "o evento cancelado" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture()), mes: mes_de_referencia()}
    end

    test "continua na célula, riscado e com o rótulo", %{conn: conn, mes: mes} do
      dia = Date.add(mes, 7)

      evento =
        evento_em(dia, ~T[19:00:00], %{title: "Culto da Noite", status: :cancelled})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#{celula(dia)} #day-event-#{evento.id}")
      assert has_element?(view, "#day-event-cancelled-#{evento.id}")

      assert element(view, "#day-event-#{evento.id} .line-through") |> render() =~
               "Culto da Noite"
    end

    test "o evento agendado não é riscado nem rotulado", %{conn: conn, mes: mes} do
      evento = evento_em(Date.add(mes, 7), ~T[19:00:00])

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      refute has_element?(view, "#day-event-cancelled-#{evento.id}")
      refute has_element?(view, "#day-event-#{evento.id} .line-through")
    end
  end

  # A posição do id no HTML é o que revela a ordem em que os eventos saíram.
  defp posicao(html, id) do
    case :binary.match(html, id) do
      {pos, _} -> pos
      :nomatch -> flunk("#{id} não está na página")
    end
  end

  describe "o filtro por banda" do
    setup %{conn: conn} do
      mes = mes_de_referencia()
      ebenezer = banda_chamada("Banda Ebenezer")
      sion = banda_chamada("Banda Sion")

      culto = evento_em(Date.add(mes, 6), ~T[19:00:00], %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: ebenezer})

      ensaio = evento_em(Date.add(mes, 9), ~T[20:00:00], %{title: "Ensaio da Sion"})
      event_band_fixture(%{event: ensaio, band: sion})

      %{
        conn: log_in_user(conn, member_fixture()),
        mes: mes,
        ebenezer: ebenezer,
        culto: culto,
        ensaio: ensaio
      }
    end

    test "filtrar pela banda deixa só os eventos dela", %{
      conn: conn,
      mes: mes,
      ebenezer: ebenezer,
      culto: culto,
      ensaio: ensaio
    } do
      {:ok, view, _html} =
        live(conn, ~p"/calendar?month=#{param(mes)}&band=#{ebenezer.id}")

      assert has_element?(view, "#day-event-#{culto.id}")
      refute has_element?(view, "#day-event-#{ensaio.id}")
    end

    test "clicar na banda grava o filtro na URL", %{conn: conn, mes: mes, ebenezer: ebenezer} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      view |> element("#filter-band-#{ebenezer.id}") |> render_click()

      assert_patched(view, ~p"/calendar?#{[month: param(mes), band: ebenezer.id]}")
    end

    test "o filtro por banda sobrevive à troca de mês", %{
      conn: conn,
      mes: mes,
      ebenezer: ebenezer
    } do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=#{ebenezer.id}")

      view |> element("#next-month") |> render_click()

      seguinte = param(Date.shift(mes, month: 1))
      assert_patched(view, ~p"/calendar?#{[month: seguinte, band: ebenezer.id]}")
    end

    test "o filtro por banda e o de tipo convivem na URL", %{
      conn: conn,
      mes: mes,
      ebenezer: ebenezer
    } do
      tipo = tipo_chamado("Culto")

      {:ok, view, _html} =
        live(conn, ~p"/calendar?month=#{param(mes)}&band=#{ebenezer.id}")

      view |> element("#filter-type-#{tipo.id}") |> render_click()

      assert_patched(
        view,
        ~p"/calendar?#{[month: param(mes), type: tipo.id, band: ebenezer.id]}"
      )
    end

    test "Todas as bandas limpa o filtro", %{conn: conn, mes: mes, ebenezer: ebenezer} do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=#{ebenezer.id}")

      view |> element("#filter-band-all") |> render_click()

      assert_patched(view, ~p"/calendar?month=#{param(mes)}")
    end

    test "a banda escolhida aparece marcada na barra", %{
      conn: conn,
      mes: mes,
      ebenezer: ebenezer
    } do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=#{ebenezer.id}")

      assert has_element?(view, "#filter-band-#{ebenezer.id}[aria-current='true']")
      refute has_element?(view, "#filter-band-all[aria-current='true']")
    end

    test "banda malformada mostra o mês inteiro, sem filtro", %{
      conn: conn,
      mes: mes,
      culto: culto,
      ensaio: ensaio
    } do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=banana")

      assert has_element?(view, "#day-event-#{culto.id}")
      assert has_element?(view, "#day-event-#{ensaio.id}")
      assert has_element?(view, "#filter-band-all[aria-current='true']")
    end

    test "banda que não existe mostra o mês inteiro, sem filtro", %{
      conn: conn,
      mes: mes,
      culto: culto
    } do
      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=999999")

      assert has_element?(view, "#day-event-#{culto.id}")
      assert has_element?(view, "#filter-band-all[aria-current='true']")
    end

    test "banda sem evento no mês mostra a mensagem, com a grade desenhada", %{
      conn: conn,
      mes: mes
    } do
      vazia = banda_chamada("Banda Sem Evento")

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}&band=#{vazia.id}")

      assert has_element?(
               view,
               "#calendar-filtered-empty",
               "Nenhum evento neste mês para o filtro escolhido."
             )

      assert has_element?(view, "#calendar-grid")
    end
  end

  describe "as bandas escaladas na célula" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture()), mes: mes_de_referencia()}
    end

    test "as duas bandas do evento aparecem abaixo do título", %{conn: conn, mes: mes} do
      culto = evento_em(Date.add(mes, 6), ~T[19:00:00], %{title: "Culto da Noite"})
      sion = banda_chamada("Banda Sion")
      ebenezer = banda_chamada("Banda Ebenezer")
      event_band_fixture(%{event: culto, band: sion})
      event_band_fixture(%{event: culto, band: ebenezer})

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert element(view, "#day-event-bands-#{culto.id}") |> render() =~
               "#{ebenezer.name}, #{sion.name}"
    end

    test "o evento sem banda não desenha a linha", %{conn: conn, mes: mes} do
      culto = evento_em(Date.add(mes, 6), ~T[19:00:00])

      {:ok, view, _html} = live(conn, ~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#day-event-#{culto.id}")
      refute has_element?(view, "#day-event-bands-#{culto.id}")
    end
  end

  describe "tempo real (#112)" do
    test "cancelar um evento aparece riscado na grade sem F5", %{conn: conn} do
      mes = mes_de_referencia()
      evento = evento_em(Date.add(mes, 9), ~T[19:00:00], %{title: "Culto da Noite"})

      {:ok, view, _html} =
        conn |> log_in_user(member_fixture()) |> live(~p"/calendar?month=#{param(mes)}")

      refute has_element?(view, "#day-event-cancelled-#{evento.id}")

      {:ok, _} = Schedule.cancel_event(evento)

      assert has_element?(view, "#day-event-cancelled-#{evento.id}")
    end

    test "a célula expandida continua expandida depois de uma atualização em outro dia", %{
      conn: conn
    } do
      mes = mes_de_referencia()
      dia = Date.add(mes, 9)
      outro_dia_evento = evento_em(Date.add(mes, 15), ~T[19:00:00])

      for n <- 1..4, do: evento_em(dia, Time.new!(8 + n, 0, 0), %{title: "Evento #{n}"})

      {:ok, view, _html} =
        conn |> log_in_user(member_fixture()) |> live(~p"/calendar?month=#{param(mes)}")

      assert has_element?(view, "#expand-day-#{dia}")
      view |> element("#expand-day-#{dia}") |> render_click()
      refute has_element?(view, "#expand-day-#{dia}")

      {:ok, _} = Schedule.cancel_event(outro_dia_evento)

      refute has_element?(view, "#expand-day-#{dia}")
    end

    test "mensagem desconhecida no tópico do calendário não derruba a view", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/calendar")

      Phoenix.PubSub.broadcast(
        ChurchBands.PubSub,
        ChurchBands.Realtime.calendar_topic(),
        :uma_mensagem_que_ninguem_conhece
      )

      assert has_element?(view, "#calendar-grid")
    end
  end
end
