defmodule ChurchBandsWeb.EventLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

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

    test "o formulário de criação recusa Líder de Banda", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/events/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "o formulário de edição tem a mesma recusa", %{conn: conn} do
      evento = event_fixture()
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/events/#{evento.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
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

      assert [evento] = Schedule.list_events()
      assert evento.location == nil
      assert evento.notes == nil
    end

    test "sem título não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = view |> form("#event-form", event: preenchido(%{"title" => ""})) |> render_submit()

      assert html =~ "informe o título do evento"
      assert Schedule.list_events() == []
    end

    test "sem tipo não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html =
        view
        |> form("#event-form", event: preenchido(%{"event_type_id" => ""}))
        |> render_submit()

      assert html =~ "escolha o tipo do evento"
      assert Schedule.list_events() == []
    end

    test "sem data não cria e o campo acusa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html =
        view
        |> form("#event-form", event: preenchido(%{"starts_at_local" => ""}))
        |> render_submit()

      assert html =~ "informe a data e a hora do evento"
      assert Schedule.list_events() == []
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
      assert Schedule.list_events() == []
    end

    test "daqui a uma hora é aceito — a fronteira é o instante", %{conn: conn} do
      daqui_a_pouco = campo_de_data(DateTime.add(LocalTime.now(), 3600, :second))
      {:ok, view, _html} = live(conn, ~p"/events/new")

      assert {:ok, _view, _html} =
               view
               |> form("#event-form", event: preenchido(%{"starts_at_local" => daqui_a_pouco}))
               |> render_submit()
               |> follow_redirect(conn)

      assert [_evento] = Schedule.list_events()
    end

    # O `<select>` só oferece tipos que existem, mas o parâmetro vem do
    # navegador e pode ser forjado.
    test "tipo forjado não cria", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = render_submit(view, "save", %{"event" => preenchido(%{"event_type_id" => "999999"})})

      assert html =~ "escolha um tipo de evento que exista"
      assert Schedule.list_events() == []
    end

    test "o validate acusa sem gravar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events/new")

      html = view |> form("#event-form", event: preenchido(%{"title" => ""})) |> render_change()

      assert html =~ "informe o título do evento"
      assert Schedule.list_events() == []
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

    test "evento que não existe devolve para a agenda", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/999999/edit")

      assert flash["error"] == "Evento não encontrado."
    end

    test "id que nem número é devolve para a agenda", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/banana/edit")

      assert flash["error"] == "Evento não encontrado."
    end
  end
end
