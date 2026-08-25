defmodule ChurchBandsWeb.EventLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Repo
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  # O nome da banda é único no sistema (DT-4) e a suíte roda em paralelo: dois
  # testes criando "Banda Ebenezer" ao mesmo tempo disputam o índice único, e
  # já travaram um no outro. O sufixo mantém o nome legível na asserção e
  # deixa cada teste sozinho com a sua banda.
  defp banda_chamada(nome, attrs) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # O que estes testes perguntam é se o evento foi **gravado**, e não o que a
  # agenda mostra. `list_events/1` passou a exigir uma faixa de tempo na US 3.3,
  # e inventar um mês aqui só para contar zero seria dizer a coisa errada.
  defp eventos_gravados, do: Repo.all(Event)

  defp hora_local(utc), do: utc |> LocalTime.to_local() |> DateTime.to_naive()

  # É assim que o `datetime-local` desenha e manda o valor: ISO, com o "T" e
  # sem os segundos.
  defp campo_de_data(utc) do
    utc |> hora_local() |> NaiveDateTime.to_iso8601() |> String.slice(0, 16)
  end

  defp preenchido(extra \\ %{}) do
    Enum.into(extra, %{
      "event_type_id" => tipo_chamado("Culto").id,
      "title" => "Culto da Noite",
      "starts_at_local" => campo_de_data(in_days(7))
    })
  end

  describe "autorização de acesso" do
    test "o formulário de criação recusa músico comum", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/events/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    # A US 3.4 abriu esta tela ao Líder de Banda: ele marca o ensaio da banda
    # dele. Quem continua de fora é quem não lidera banda nenhuma.
    test "o formulário de criação aceita Líder de Banda", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, view, _html} = conn |> log_in_user(leader) |> live(~p"/events/new")

      assert has_element?(view, "#event-form")
    end

    test "o formulário de edição recusa quem não gerencia o evento", %{conn: conn} do
      evento = event_fixture()
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/#{evento.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para gerenciar este evento."
    end

    test "visitante é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/events/new")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "criar" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, worship_leader_fixture())}
    end

    test "cria o evento e vai para o detalhe dele", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _view, html} =
               view
               |> form("#event-form", event: preenchido(%{"location" => "Templo sede"}))
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Evento Culto da Noite criado."
      assert html =~ "Templo sede"
    end

    test "cria sem local e sem observações", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _view, _html} =
               view
               |> form("#event-form", event: preenchido())
               |> render_submit()
               |> follow_redirect(conn)

      assert [evento] = eventos_gravados()
      assert evento.location == nil
      assert evento.notes == nil
    end

    test "sem título não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = view |> form("#event-form", event: preenchido(%{"title" => ""})) |> render_submit()

      assert html =~ "informe o título do evento"
      assert eventos_gravados() == []
    end

    test "sem tipo não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html =
        view
        |> form("#event-form", event: preenchido(%{"event_type_id" => ""}))
        |> render_submit()

      assert html =~ "escolha o tipo do evento"
      assert eventos_gravados() == []
    end

    test "sem data não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html =
        view
        |> form("#event-form", event: preenchido(%{"starts_at_local" => ""}))
        |> render_submit()

      assert html =~ "informe a data e a hora do evento"
      assert eventos_gravados() == []
    end

    test "título de um caractere fala do tamanho", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = view |> form("#event-form", event: preenchido(%{"title" => "C"})) |> render_submit()

      assert html =~ "precisa ter entre 2 e 80 caracteres"
    end

    # A recusa da data cai no campo, e não num flash: quem digitou o ano
    # errado precisa ver a mensagem ao lado do que digitou.
    test "data de ontem é recusada no próprio campo", %{conn: conn} do
      ontem = campo_de_data(DateTime.add(LocalTime.now(), -1, :day))
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html =
        view
        |> form("#event-form", event: preenchido(%{"starts_at_local" => ontem}))
        |> render_submit()

      assert html =~ "não dá para marcar um evento no passado"
      assert eventos_gravados() == []
    end

    test "daqui a uma hora é aceito — a fronteira é o instante", %{conn: conn} do
      daqui_a_pouco = campo_de_data(DateTime.add(LocalTime.now(), 3600, :second))
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _view, _html} =
               view
               |> form("#event-form", event: preenchido(%{"starts_at_local" => daqui_a_pouco}))
               |> render_submit()
               |> follow_redirect(conn)

      assert [_evento] = eventos_gravados()
    end

    # O `<select>` só oferece tipos que existem, mas o parâmetro vem do
    # navegador e pode ser forjado.
    test "tipo forjado não cria", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = render_submit(view, "save", %{"event" => preenchido(%{"event_type_id" => "999999"})})

      assert html =~ "escolha um tipo de evento que exista"
      assert eventos_gravados() == []
    end

    test "o validate acusa sem gravar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = view |> form("#event-form", event: preenchido(%{"title" => ""})) |> render_change()

      assert html =~ "informe o título do evento"
      assert eventos_gravados() == []
    end

    test "o formulário oferece os tipos cadastrados", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = render(view)

      for nome <- ["Culto", "Ensaio", "Confraternização"], do: assert(html =~ nome)
    end

    test "traz o atalho para gerenciar tipos", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert has_element?(view, "#manage-event-types-link")
    end
  end

  describe "editar" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "corrige o título e volta para o detalhe", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noit"})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}/edit")

      assert {:ok, _view, html} =
               view
               |> form("#event-form", event: %{"title" => "Culto da Noite"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/events/#{evento.id}")

      assert html =~ "Evento Culto da Noite atualizado."
    end

    test "corrige um culto que já aconteceu", %{conn: conn} do
      evento =
        event_fixture(%{
          title: "Culto errado",
          starts_at: DateTime.add(LocalTime.now(), -7, :day)
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}/edit")

      assert {:ok, _view, _html} =
               view
               |> form("#event-form", event: %{"title" => "Culto certo"})
               |> render_submit()
               |> follow_redirect(conn)

      assert Schedule.get_event(evento.id).title == "Culto certo"
    end

    # É o teste do critério 24: o campo abre com 19:00, e salvar sem mexer não
    # anda com o horário.
    test "o campo abre com a hora de parede e salvar sem mexer não a desloca", %{conn: conn} do
      evento = event_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}/edit")

      assert render(view) =~ campo_de_data(evento.starts_at)

      view
      |> form("#event-form", event: %{"starts_at_local" => campo_de_data(evento.starts_at)})
      |> render_submit()

      assert Schedule.get_event(evento.id).starts_at == evento.starts_at
    end

    test "muda a data para outro dia futuro", %{conn: conn} do
      evento = event_fixture()
      nova = in_days(30)
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}/edit")

      view
      |> form("#event-form", event: %{"starts_at_local" => campo_de_data(nova)})
      |> render_submit()

      assert hora_local(Schedule.get_event(evento.id).starts_at) ==
               NaiveDateTime.truncate(hora_local(nova), :second) |> Map.put(:second, 0)
    end

    test "apagar o título na edição acusa sem gravar", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}/edit")

      html = view |> form("#event-form", event: %{"title" => ""}) |> render_submit()

      assert html =~ "informe o título do evento"
      assert Schedule.get_event(evento.id).title == "Culto da Noite"
    end

    # Desde a US 3.4 quem recusa é o hook `:ensure_event_manager`, antes do
    # mount — por isso a redireção deixou de ser `live_redirect`.
    test "evento que não existe devolve para a agenda", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/999999/edit")

      assert flash["error"] == "Evento não encontrado."
    end

    test "id que nem número é devolve para a agenda", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/banana/edit")

      assert flash["error"] == "Evento não encontrado."
    end
  end

  describe "o Líder de Banda marca o ensaio da banda dele" do
    setup %{conn: conn} do
      lider = member_fixture()
      banda = banda_chamada("Banda Ebenezer", %{leader: lider})

      # Tipos próprios, e não os três da migration: criar um evento segura a
      # linha do tipo pela chave estrangeira, e a suíte tem um teste que esvazia
      # a tabela de tipos inteira. Além disso o teste passa a dizer o que
      # importa — *marcado* e *não marcado* —, e não um nome de tipo.
      %{
        conn: log_in_user(conn, lider),
        lider: lider,
        banda: banda,
        marcado: event_type_fixture(%{band_leader_can_create: true}),
        solto: event_type_fixture(%{})
      }
    end

    defp ensaio_preenchido(tipo, extra) do
      Enum.into(extra, %{
        "event_type_id" => tipo.id,
        "title" => "Ensaio da semana",
        "starts_at_local" => campo_de_data(in_days(7))
      })
    end

    test "o seletor de tipo mostra só os tipos marcados", %{
      conn: conn,
      marcado: marcado,
      solto: solto
    } do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert has_element?(view, "option[value='#{marcado.id}']")
      refute has_element?(view, "option[value='#{solto.id}']")
    end

    # Ir para `/event-types` não levaria a lugar nenhum: a tela é de acesso
    # total.
    test "não vê o atalho de gerenciar tipos", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      refute has_element?(view, "#manage-event-types-link")
    end

    test "quem lidera uma banda só a vê preenchida, sem escolha", %{conn: conn, banda: banda} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert has_element?(view, "#single-leading-band", banda.name)
      assert has_element?(view, "input[type=hidden][name='event[band_id]'][value='#{banda.id}']")
      refute has_element?(view, "select[name='event[band_id]']")
    end

    test "quem lidera duas bandas escolhe qual entra escalada", %{conn: conn, lider: lider} do
      outra = banda_chamada("Banda Sion", %{leader: lider})

      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert has_element?(view, "select[name='event[band_id]'] option[value='#{outra.id}']")
      refute has_element?(view, "#single-leading-band")
    end

    test "o ensaio criado já nasce com a banda escalada", %{
      conn: conn,
      banda: banda,
      marcado: marcado
    } do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _show, html} =
               view
               |> form("#event-form", event: ensaio_preenchido(marcado, %{"band_id" => banda.id}))
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Evento Ensaio da semana criado."
      assert [evento] = eventos_gravados()
      assert [%{band_id: escalada}] = Schedule.list_event_bands(evento)
      assert escalada == banda.id
    end

    test "o tipo forçado que ele não pode marcar acusa no campo", %{
      conn: conn,
      banda: banda,
      marcado: marcado,
      solto: solto
    } do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      params = ensaio_preenchido(marcado, %{"band_id" => banda.id, "event_type_id" => solto.id})

      html = render_submit(view, "save", %{"event" => params})

      assert html =~ "escolha um tipo que você pode marcar"
      assert eventos_gravados() == []
    end

    test "a banda forçada que ele não lidera acusa no campo", %{conn: conn, marcado: marcado} do
      alheia = band_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/new")

      params = ensaio_preenchido(marcado, %{"band_id" => alheia.id})
      html = render_submit(view, "save", %{"event" => params})

      assert html =~ "escolha uma banda que você lidera"
      assert eventos_gravados() == []
    end

    test "o choque de horário acusa no campo de data", %{
      conn: conn,
      banda: banda,
      marcado: marcado
    } do
      culto = event_fixture(%{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})

      {:ok, view, _html} = live(conn, ~p"/events/new")

      params =
        ensaio_preenchido(marcado, %{
          "band_id" => banda.id,
          "starts_at_local" => campo_de_data(DateTime.add(culto.starts_at, 60 * 60))
        })

      html = render_submit(view, "save", %{"event" => params})

      assert html =~ "#{banda.name} já está escalada em Culto da Noite, no mesmo horário"
      assert Enum.map(eventos_gravados(), & &1.id) == [culto.id]
    end

    test "marcar no passado tem a mesma recusa de sempre", %{
      conn: conn,
      banda: banda,
      marcado: marcado
    } do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      ontem = campo_de_data(DateTime.add(LocalTime.now(), -1, :day))
      params = ensaio_preenchido(marcado, %{"band_id" => banda.id, "starts_at_local" => ontem})

      assert render_submit(view, "save", %{"event" => params}) =~
               "não dá para marcar um evento no passado"

      assert eventos_gravados() == []
    end
  end

  describe "quem não lidera banda nenhuma" do
    test "é recusado ao forçar o formulário de criação", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/events/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end
  end

  describe "o Líder de Banda edita o próprio ensaio" do
    setup %{conn: conn} do
      lider = member_fixture()
      banda = banda_chamada("Banda Ebenezer", %{leader: lider})
      # Tipo próprio, e não o "Ensaio" da migration: um destes testes o
      # desmarca, e mexer na linha que a suíte inteira lê poria os testes para
      # esperar uns pelos outros.
      tipo = event_type_fixture(%{band_leader_can_create: true})
      ensaio = event_fixture(%{event_type: tipo, title: "Ensaio da semana"})
      escala = event_band_fixture(%{event: ensaio, band: banda})

      %{conn: log_in_user(conn, lider), banda: banda, ensaio: ensaio, escala: escala, tipo: tipo}
    end

    test "corrige a hora do próprio ensaio", %{conn: conn, ensaio: ensaio} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}/edit")

      nova = DateTime.add(ensaio.starts_at, 1, :day)

      assert {:ok, _show, html} =
               view
               |> form("#event-form", event: %{"starts_at_local" => campo_de_data(nova)})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Evento Ensaio da semana atualizado."
      assert Schedule.get_event(ensaio.id).starts_at == nova
    end

    # A escala não se edita por aqui: o formulário de banda é só da criação.
    test "o formulário de edição não oferece banda", %{conn: conn, ensaio: ensaio} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}/edit")

      refute has_element?(view, "select[name='event[band_id]']")
      refute has_element?(view, "#single-leading-band")
    end

    test "desescalar a banda tira o ensaio das mãos dele", %{
      conn: conn,
      ensaio: ensaio,
      escala: escala
    } do
      {:ok, _escala} = Schedule.unschedule_band(escala)

      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/#{ensaio.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para gerenciar este evento."
    end

    test "desmarcar o tipo tira o ensaio das mãos dele", %{
      conn: conn,
      ensaio: ensaio,
      tipo: tipo
    } do
      {:ok, _tipo} = Schedule.update_event_type(tipo, %{band_leader_can_create: false})

      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/#{ensaio.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para gerenciar este evento."
    end

    test "o líder de outra banda não edita este ensaio", %{conn: conn, ensaio: ensaio} do
      outro = member_fixture()
      band_fixture(%{leader: outro})

      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               conn |> log_in_user(outro) |> live(~p"/events/#{ensaio.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para gerenciar este evento."
    end

    test "mudar a data para cima de um culto da banda acusa no campo", %{
      conn: conn,
      banda: banda,
      ensaio: ensaio
    } do
      culto = event_fixture(%{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})

      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}/edit")

      dentro = campo_de_data(DateTime.add(culto.starts_at, 60 * 60))

      html =
        view |> form("#event-form", event: %{"starts_at_local" => dentro}) |> render_submit()

      assert html =~ "#{banda.name} já está escalada em Culto da Noite, no mesmo horário"
      assert Schedule.get_event(ensaio.id).starts_at == ensaio.starts_at
    end
  end

  describe "quem tem acesso total no formulário" do
    test "vê todos os tipos e nenhum campo de banda", %{conn: conn} do
      marcado = event_type_fixture(%{band_leader_can_create: true})
      solto = event_type_fixture(%{})

      {:ok, view, _html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/events/new")

      assert has_element?(view, "option[value='#{marcado.id}']")
      assert has_element?(view, "option[value='#{solto.id}']")
      refute has_element?(view, "select[name='event[band_id]']")
      refute has_element?(view, "#single-leading-band")
      assert has_element?(view, "#manage-event-types-link")
    end

    test "o evento que ele cria nasce sem banda escalada", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _show, _html} =
               view
               |> form("#event-form", event: preenchido())
               |> render_submit()
               |> follow_redirect(conn)

      assert [evento] = eventos_gravados()
      assert Schedule.list_event_bands(evento) == []
    end
  end
end
