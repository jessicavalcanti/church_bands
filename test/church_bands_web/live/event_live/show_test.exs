defmodule ChurchBandsWeb.EventLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  describe "quem abre o detalhe" do
    test "músico comum vê o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})
      conn = log_in_user(conn, member_fixture())

      {:ok, _view, html} = live(conn, ~p"/events/#{evento.id}")

      assert html =~ "Culto da Noite"
    end

    test "Líder de Banda vê o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})
      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, _view, html} = conn |> log_in_user(leader) |> live(~p"/events/#{evento.id}")

      assert html =~ "Culto da Noite"
    end

    test "visitante é mandado para o login", %{conn: conn} do
      evento = event_fixture()

      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, ~p"/events/#{evento.id}")

      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "os botões de escrita" do
    test "músico comum não vê nenhum deles", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      refute has_element?(view, "#edit-event")
      refute has_element?(view, "#cancel-event")
      refute has_element?(view, "#delete-event")
    end

    test "músico comum não vê reabrir no evento cancelado", %{conn: conn} do
      evento = event_fixture(%{status: :cancelled})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      refute has_element?(view, "#reopen-event")
    end

    test "Líder de Louvor vê editar, cancelar e excluir", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} =
        conn |> log_in_user(worship_leader_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#edit-event")
      assert has_element?(view, "#cancel-event")
      assert has_element?(view, "#delete-event")
    end

    test "Pastor vê reabrir no evento cancelado", %{conn: conn} do
      evento = event_fixture(%{status: :cancelled})

      {:ok, view, _html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#reopen-event")
    end

    # Voltar para a agenda é de quem vê a tela, e não de quem escreve nela.
    test "músico comum continua com o caminho de volta", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#back-to-calendar")
    end
  end

  # Esconder o botão não é autorização: o evento chega pelo socket, e quem sabe
  # disso o dispara sem botão nenhum. A tela recusa as três escritas no
  # servidor.
  describe "a escrita forçada pelo socket" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, member_fixture())}
    end

    test "cancelar forçado não grava e recebe a recusa", %{conn: conn} do
      evento = event_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert render_click(view, "cancel") =~ "Você não tem permissão para alterar este evento."
      assert Schedule.get_event(evento.id).status == :scheduled
    end

    test "reabrir forçado não grava e recebe a recusa", %{conn: conn} do
      evento = event_fixture(%{status: :cancelled})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert render_click(view, "reopen") =~ "Você não tem permissão para alterar este evento."
      assert Schedule.get_event(evento.id).status == :cancelled
    end

    test "excluir forçado não apaga e recebe a recusa", %{conn: conn} do
      evento = event_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert render_click(view, "delete") =~ "Você não tem permissão para alterar este evento."
      assert Schedule.get_event(evento.id) != nil
    end
  end

  describe "o detalhe" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "mostra título, tipo, data, hora e local", %{conn: conn} do
      evento =
        event_fixture(%{
          title: "Culto da Noite",
          location: "Templo sede",
          event_type: tipo_chamado("Culto")
        })

      {:ok, view, html} = live(conn, ~p"/events/#{evento.id}")

      assert html =~ "Culto da Noite"
      assert html =~ "Culto"
      assert element(view, "#event-date") |> render() =~ LocalTime.format(evento.starts_at, :date)
      assert element(view, "#event-time") |> render() =~ LocalTime.format(evento.starts_at, :time)
      assert element(view, "#event-location") |> render() =~ "Templo sede"
    end

    # O critério 23: o evento gravado para as 19h no fuso da igreja aparece
    # como 19:00, mesmo com o servidor em UTC.
    test "a hora aparece no fuso da igreja, e não em UTC", %{conn: conn} do
      dezenove_horas =
        in_days(7)
        |> LocalTime.to_local()
        |> DateTime.to_date()
        |> DateTime.new!(~T[19:00:00], LocalTime.time_zone())
        |> DateTime.shift_zone!("Etc/UTC")

      evento = event_fixture(%{starts_at: dezenove_horas})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#event-time") |> render() =~ "19:00"
    end

    test "o evento sem local diz que não foi informado", %{conn: conn} do
      evento = event_fixture(%{location: nil})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#event-location") |> render() =~ "Não informado"
    end

    test "as observações aparecem quando existem", %{conn: conn} do
      evento = event_fixture(%{notes: "Chegar às 18h para a passagem de som"})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#event-notes") |> render() =~ "Chegar às 18h"
    end

    test "sem observações o bloco não aparece", %{conn: conn} do
      evento = event_fixture(%{notes: nil})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      refute has_element?(view, "#event-notes")
    end

    test "evento que não existe devolve para a agenda", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/999999")

      assert flash["error"] == "Evento não encontrado."
    end

    test "id que nem número é devolve para a agenda", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/banana")

      assert flash["error"] == "Evento não encontrado."
    end
  end

  describe "cancelar e reabrir" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "cancelar troca o status, avisa e mantém o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_click(view, "cancel")

      assert html =~ "Evento Culto da Noite cancelado."
      assert has_element?(view, "#event-cancelled-badge")
      assert Schedule.get_event(evento.id).status == :cancelled
    end

    test "reabrir devolve o evento a agendado", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite", status: :cancelled})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_click(view, "reopen")

      assert html =~ "Evento Culto da Noite reaberto."
      refute has_element?(view, "#event-cancelled-badge")
      assert Schedule.get_event(evento.id).status == :scheduled
    end

    # O par é mutuamente exclusivo pelo status: num evento que a igreja
    # divulgou não se clica em "alternar" por engano.
    test "o evento agendado oferece cancelar, e não reabrir", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(view, "#cancel-event")
      refute has_element?(view, "#reopen-event")
    end

    test "o evento cancelado oferece reabrir, e não cancelar", %{conn: conn} do
      evento = event_fixture(%{status: :cancelled})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(view, "#reopen-event")
      refute has_element?(view, "#cancel-event")
    end

    test "cancelar um evento que já passou é permitido", %{conn: conn} do
      evento = event_fixture(%{starts_at: DateTime.add(LocalTime.now(), -2, :day)})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      render_click(view, "cancel")

      assert Schedule.get_event(evento.id).status == :cancelled
    end

    test "cancelar pede confirmação nomeando o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#cancel-event") |> render() =~
               "Cancelar o evento Culto da Noite?"
    end

    test "reabrir pede confirmação nomeando o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite", status: :cancelled})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#reopen-event") |> render() =~ "Reabrir o evento Culto da Noite?"
    end
  end

  describe "excluir" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, worship_leader_fixture())}
    end

    test "exclui o evento e volta para a agenda", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert {:ok, _view, html} =
               view
               |> render_click("delete")
               |> follow_redirect(conn, ~p"/calendar")

      assert html =~ "Evento Culto da Noite excluído."
      assert Schedule.get_event(evento.id) == nil
    end

    test "excluir pede confirmação nomeando o evento", %{conn: conn} do
      evento = event_fixture(%{title: "Culto da Noite"})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert element(view, "#delete-event") |> render() =~
               "Excluir o evento Culto da Noite?"
    end
  end

  describe "navegação" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "oferece voltar para a agenda e editar", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(view, "#back-to-calendar")
      assert element(view, "#edit-event") |> render() =~ "/events/#{evento.id}/edit"
    end
  end
end
