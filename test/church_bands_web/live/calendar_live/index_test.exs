defmodule ChurchBandsWeb.CalendarLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  defp dias_atras(dias), do: DateTime.add(LocalTime.now(), -dias, :day)

  describe "autorização de acesso" do
    test "Pastor abre a agenda", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/calendar")
      assert has_element?(view, "#new-event-button")
    end

    test "Líder de Louvor abre a agenda", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/calendar")
      assert has_element?(view, "#new-event-button")
    end

    # A leitura ampla chega na US 3.3; até lá nem olhar é de todo mundo.
    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/calendar")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    # Liderar uma banda ainda não dá acesso ao calendário: a criação pelo Líder
    # de Banda depende da escala, e ela nasce na US 3.4.
    test "Líder de Banda tem o acesso negado", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/calendar")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/calendar")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "a lista" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "a agenda sem evento nenhum mostra o estado vazio", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert has_element?(view, "#calendar-empty")
      assert render(view) =~ "Nenhum evento no calendário ainda."
    end

    test "o evento aparece com título, data, hora, tipo e local", %{conn: conn} do
      evento =
        event_fixture(%{
          title: "Culto da Noite",
          location: "Templo sede",
          event_type: tipo_chamado("Culto")
        })

      {:ok, view, _html} = live(conn, ~p"/calendar")

      cartao = element(view, "#event-#{evento.id}") |> render()

      assert cartao =~ "Culto da Noite"
      assert cartao =~ "Templo sede"
      assert cartao =~ "Culto"
      assert cartao =~ LocalTime.format(evento.starts_at, :short)
    end

    test "os eventos futuros vêm do mais próximo ao mais distante", %{conn: conn} do
      distante = event_fixture(%{title: "Distante", starts_at: in_days(30)})
      proximo = event_fixture(%{title: "Próximo", starts_at: in_days(2)})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      html = element(view, "#upcoming-events") |> render()

      assert index_of(html, "event-#{proximo.id}") < index_of(html, "event-#{distante.id}")
    end

    test "o que já aconteceu desce para baixo do separador", %{conn: conn} do
      passado = event_fixture(%{title: "Culto passado", starts_at: dias_atras(3)})
      futuro = event_fixture(%{title: "Culto futuro"})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert has_element?(view, "#past-separator")
      assert render(view) =~ "Já aconteceram"
      assert has_element?(view, "#past-events #event-#{passado.id}")
      assert has_element?(view, "#upcoming-events #event-#{futuro.id}")
    end

    # Do mais recente para o mais antigo: o culto de ontem interessa mais do
    # que o de seis meses atrás.
    test "o passado vem do mais recente para o mais antigo", %{conn: conn} do
      antigo = event_fixture(%{title: "Antigo", starts_at: dias_atras(30)})
      recente = event_fixture(%{title: "Recente", starts_at: dias_atras(1)})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      html = element(view, "#past-events") |> render()

      assert index_of(html, "event-#{recente.id}") < index_of(html, "event-#{antigo.id}")
    end

    test "sem evento passado o separador não aparece", %{conn: conn} do
      event_fixture()

      {:ok, view, _html} = live(conn, ~p"/calendar")

      refute has_element?(view, "#past-separator")
    end

    test "o evento cancelado continua na lista, riscado e com o rótulo", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite", status: :cancelled})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert has_element?(view, "#event-cancelled-#{evento.id}")
      assert element(view, "#event-#{evento.id} .line-through") |> render() =~ "Culto da Noite"
    end

    test "o evento sem local não mostra separador de local sozinho", %{conn: conn} do
      evento = event_fixture(%{title: "Sem local", location: nil})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      refute element(view, "#event-#{evento.id}") |> render() =~ "·&nbsp;"
    end

    test "clicar no cartão leva ao detalhe do evento", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert element(view, "#event-#{evento.id}") |> render() =~ ~s|href="/events/#{evento.id}"|
    end
  end

  # A posição do id no HTML é o que revela a ordem em que os cartões saíram.
  defp index_of(html, id) do
    case :binary.match(html, id) do
      {pos, _} -> pos
      :nomatch -> flunk("#{id} não está na página")
    end
  end
end
