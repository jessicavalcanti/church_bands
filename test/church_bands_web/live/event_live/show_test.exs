defmodule ChurchBandsWeb.EventLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands
  alias ChurchBands.LocalTime
  alias ChurchBands.Repo
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.EventBandSong

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

  defp evento_em(instante, attrs) do
    attrs |> Map.new() |> Map.put(:starts_at, instante) |> event_fixture()
  end

  # Onde cada texto aparece no HTML: é assim que a suíte confere ordem de lista
  # sem depender de um analisador de DOM.
  defp posicoes(html, textos) do
    Enum.map(textos, fn texto -> html |> :binary.match(texto) |> elem(0) end)
  end

  # Uma música no repertório **e** no set (US 3.6), que é o estado normal de um
  # item. `key_da_banda` é o tom do repertório; `key`, a exceção deste evento.
  defp no_set(event_band, band, titulo, position, opts \\ []) do
    {key_da_banda, opts} = Keyword.pop(opts, :key_da_banda, "C")

    entry =
      band_repertoire_fixture(%{band: band, song: song_fixture(title: titulo), key: key_da_banda})

    event_band_song_fixture(%{
      event_band: event_band,
      song: entry.song,
      position: position,
      key: opts[:key]
    })
  end

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

  describe "o bloco de bandas" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, worship_leader_fixture()), evento: event_fixture()}
    end

    test "o evento sem escala diz que não há banda", %{conn: conn, evento: evento} do
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(view, "#event-bands-empty", "Nenhuma banda escalada.")
    end

    test "as bandas escaladas aparecem com link para cada uma", %{conn: conn, evento: evento} do
      banda = banda_chamada("Banda Ebenezer")
      event_band_fixture(%{event: evento, band: banda})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-#{banda.id} a[href='/bands/#{banda.id}']")
      assert render(view) =~ banda.name
    end

    test "as bandas saem em ordem alfabética", %{conn: conn, evento: evento} do
      sion = banda_chamada("Banda Sion")
      ebenezer = banda_chamada("Banda Ebenezer")

      for banda <- [sion, ebenezer] do
        event_band_fixture(%{event: evento, band: banda})
      end

      {:ok, _view, html} = live(conn, ~p"/events/#{evento.id}")

      lugares = posicoes(html, [ebenezer.name, sion.name])

      assert lugares == Enum.sort(lugares)
    end
  end

  describe "escalar uma banda" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, worship_leader_fixture()), evento: event_fixture()}
    end

    test "escala e avisa nomeando banda e evento", %{conn: conn, evento: evento} do
      banda = banda_chamada("Banda Ebenezer")
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html =
        view
        |> form("#schedule-band-form", event_band: %{band_id: banda.id})
        |> render_submit()

      assert html =~ "#{banda.name} escalada em #{evento.title}."
      assert has_element?(view, "#event-band-#{banda.id}")
    end

    test "a banda escalada some da lista de candidatas", %{conn: conn, evento: evento} do
      banda = banda_chamada("Banda Ebenezer")
      event_band_fixture(%{event: evento, band: banda})
      banda_chamada("Banda Sion")

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      refute has_element?(view, "#schedule-band-form option[value='#{banda.id}']")
      assert has_element?(view, "#schedule-band-form")
    end

    test "sem candidata sobrando o formulário dá lugar ao recado", %{conn: conn, evento: evento} do
      event_band_fixture(%{event: evento, band: band_fixture()})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      refute has_element?(view, "#schedule-band-form")
      assert has_element?(view, "#no-schedulable-bands")
    end

    # O seletor esconde as escaladas, então quem manda uma repetida forçou o
    # formulário — e é o índice único que tem a palavra final.
    test "banda repetida forçada não grava e a recusa aparece", %{conn: conn, evento: evento} do
      banda = band_fixture()
      event_band_fixture(%{event: evento, band: banda})
      band_fixture()

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_submit(view, "schedule", %{"event_band" => %{"band_id" => banda.id}})

      assert html =~ "Escolha uma banda da lista que ainda não está escalada."
      assert length(Schedule.list_event_bands(evento)) == 1
    end

    test "banda que não existe forçada não grava", %{conn: conn, evento: evento} do
      band_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_submit(view, "schedule", %{"event_band" => %{"band_id" => "999999"}})

      assert html =~ "Escolha uma banda da lista que ainda não está escalada."
      assert Schedule.list_event_bands(evento) == []
    end

    test "a banda ocupada no mesmo horário é recusada nomeando o outro evento", %{
      conn: conn,
      evento: evento
    } do
      banda = banda_chamada("Banda Ebenezer")
      culto = evento_em(DateTime.add(evento.starts_at, 60 * 60), %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_submit(view, "schedule", %{"event_band" => %{"band_id" => banda.id}})

      assert html =~ "#{banda.name} já está escalada em Culto da Noite, no mesmo horário."
      assert Schedule.list_event_bands(evento) == []
    end
  end

  describe "desescalar uma banda" do
    setup %{conn: conn} do
      evento = event_fixture()
      banda = banda_chamada("Banda Ebenezer")
      event_band_fixture(%{event: evento, band: banda})

      %{conn: log_in_user(conn, worship_leader_fixture()), evento: evento, banda: banda}
    end

    test "tira a banda do bloco e avisa", %{conn: conn, evento: evento, banda: banda} do
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = view |> element("#unschedule-band-#{banda.id}") |> render_click()

      assert html =~ "#{banda.name} saiu da escala de #{evento.title}."
      refute has_element?(view, "#event-band-#{banda.id}")
      assert has_element?(view, "#event-bands-empty")
    end

    test "a confirmação nomeia a banda", %{conn: conn, evento: evento, banda: banda} do
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert has_element?(
               view,
               "#unschedule-band-#{banda.id}[data-confirm='Desescalar a #{banda.name} deste evento?']"
             )
    end

    # O set vai junto pelo `on_delete: :delete_all` (US 3.6), e uma confirmação
    # que não diz isso faz perder meia hora de trabalho por um clique que
    # parecia inofensivo.
    test "a confirmação conta as músicas do set que serão perdidas", %{
      conn: conn,
      evento: evento,
      banda: banda
    } do
      escala = Schedule.get_event_band(evento.id, banda.id)

      for titulo <- ["Aleluia", "Santo", "Grande é o Senhor"] do
        entry = band_repertoire_fixture(%{band: banda, song: song_fixture(%{title: titulo})})
        event_band_song_fixture(%{event_band: escala, song: entry.song})
      end

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert view |> element("#unschedule-band-#{banda.id}") |> render() =~
               "As 3 músicas do set dela neste evento serão perdidas."

      assert has_element?(view, "#set-count-#{banda.id}", "3 no set")
    end

    test "uma música só é dita no singular", %{conn: conn, evento: evento, banda: banda} do
      escala = Schedule.get_event_band(evento.id, banda.id)
      entry = band_repertoire_fixture(%{band: banda})
      event_band_song_fixture(%{event_band: escala, song: entry.song})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert view |> element("#unschedule-band-#{banda.id}") |> render() =~
               "A 1 música do set dela neste evento será perdida."
    end

    test "desescalar leva o set junto", %{conn: conn, evento: evento, banda: banda} do
      escala = Schedule.get_event_band(evento.id, banda.id)
      entry = band_repertoire_fixture(%{band: banda})
      event_band_song_fixture(%{event_band: escala, song: entry.song})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      view |> element("#unschedule-band-#{banda.id}") |> render_click()

      assert Schedule.get_event_band(evento.id, banda.id) == nil
      assert Repo.aggregate(EventBandSong, :count) == 0
    end

    # Banda sem set continua com a frase simples: dizer "as 0 músicas" seria
    # anunciar uma perda que não existe.
    test "a banda sem set não ganha contagem nenhuma", %{
      conn: conn,
      evento: evento,
      banda: banda
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      refute view |> element("#unschedule-band-#{banda.id}") |> render() =~ "músicas do set"
      refute has_element?(view, "#set-count-#{banda.id}")
    end

    # O id vem do navegador e poderia apontar para a escala de outro evento.
    test "a banda de outro evento forçada não apaga nada", %{conn: conn, evento: evento} do
      outra = band_fixture()
      event_band_fixture(%{event: event_fixture(), band: outra})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_click(view, "unschedule", %{"id" => outra.id})

      assert html =~ "Esta banda não está escalada neste evento."
      assert length(Schedule.list_event_bands(evento)) == 1
    end
  end

  describe "o Líder de Banda no próprio ensaio" do
    setup %{conn: conn} do
      lider = member_fixture()
      banda = banda_chamada("Banda Ebenezer", %{leader: lider})
      # Tipos próprios, e não os três da migration: criar um evento segura a
      # linha do tipo pela chave estrangeira, e a suíte tem um teste que esvazia
      # a tabela de tipos inteira.
      marcado = event_type_fixture(%{band_leader_can_create: true})
      ensaio = event_fixture(%{event_type: marcado})
      event_band_fixture(%{event: ensaio, band: banda})

      %{
        conn: log_in_user(conn, lider),
        ensaio: ensaio,
        banda: banda,
        lider: lider,
        marcado: marcado,
        solto: event_type_fixture(%{})
      }
    end

    test "vê editar e cancelar, e não vê excluir", %{conn: conn, ensaio: ensaio} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      assert has_element?(view, "#edit-event")
      assert has_element?(view, "#cancel-event")
      refute has_element?(view, "#delete-event")
    end

    test "vê reabrir no próprio ensaio cancelado", %{
      conn: conn,
      banda: banda,
      lider: lider,
      marcado: marcado
    } do
      cancelado = event_fixture(%{event_type: marcado, status: :cancelled})
      event_band_fixture(%{event: cancelado, band: banda})

      {:ok, view, _html} = conn |> log_in_user(lider) |> live(~p"/events/#{cancelado.id}")

      assert has_element?(view, "#reopen-event")
    end

    test "cancela o próprio ensaio", %{conn: conn, ensaio: ensaio} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      assert render_click(view, "cancel") =~ "Evento #{ensaio.title} cancelado."
      assert Schedule.get_event(ensaio.id).status == :cancelled
    end

    test "não escala nem desescala ninguém", %{conn: conn, ensaio: ensaio, banda: banda} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      assert has_element?(view, "#event-band-#{banda.id}")
      refute has_element?(view, "#schedule-band-form")
      refute has_element?(view, "#unschedule-band-#{banda.id}")
    end

    test "escalar forçado não grava e recebe a recusa", %{conn: conn, ensaio: ensaio} do
      outra = band_fixture()
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      html = render_submit(view, "schedule", %{"event_band" => %{"band_id" => outra.id}})

      assert html =~ "Você não tem permissão para alterar este evento."
      assert length(Schedule.list_event_bands(ensaio)) == 1
    end

    test "desescalar forçado não grava e recebe a recusa", %{
      conn: conn,
      ensaio: ensaio,
      banda: banda
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      html = render_click(view, "unschedule", %{"id" => banda.id})

      assert html =~ "Você não tem permissão para alterar este evento."
      assert length(Schedule.list_event_bands(ensaio)) == 1
    end

    test "excluir forçado não apaga e recebe a recusa", %{conn: conn, ensaio: ensaio} do
      {:ok, view, _html} = live(conn, ~p"/events/#{ensaio.id}")

      html = render_click(view, "delete")

      assert html =~ "Você não tem permissão para alterar este evento."
      assert Schedule.get_event(ensaio.id)
    end

    test "não gerencia o culto que não é da banda dele", %{conn: conn, solto: solto} do
      culto = event_fixture(%{event_type: solto})

      {:ok, view, _html} = live(conn, ~p"/events/#{culto.id}")

      refute has_element?(view, "#edit-event")
      refute has_element?(view, "#cancel-event")
      refute has_element?(view, "#delete-event")
    end

    test "cancelar forçado num evento que não é dele é recusado", %{conn: conn, solto: solto} do
      culto = event_fixture(%{event_type: solto})
      {:ok, view, _html} = live(conn, ~p"/events/#{culto.id}")

      assert render_click(view, "cancel") =~ "Você não tem permissão para alterar este evento."
      assert Schedule.get_event(culto.id).status == :scheduled
    end
  end

  describe "excluir com banda escalada" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture()), evento: event_fixture()}
    end

    test "o evento com duas bandas não é excluído, e a recusa conta as duas", %{
      conn: conn,
      evento: evento
    } do
      for _ <- 1..2, do: event_band_fixture(%{event: evento, band: band_fixture()})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      html = render_click(view, "delete")

      assert html =~ "#{evento.title} tem 2 bandas escaladas."
      assert html =~ "Cancele o evento em vez de excluí-lo."
      assert Schedule.get_event(evento.id)
    end

    test "a recusa fala no singular quando é uma banda só", %{conn: conn, evento: evento} do
      event_band_fixture(%{event: evento, band: band_fixture()})

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")

      assert render_click(view, "delete") =~ "#{evento.title} tem 1 banda escalada."
    end
  end

  describe "reabrir com a banda ocupada" do
    test "a recusa nomeia banda e evento, e o evento continua cancelado", %{conn: conn} do
      banda = banda_chamada("Banda Ebenezer")
      cancelado = event_fixture(%{status: :cancelled})
      event_band_fixture(%{event: cancelado, band: banda})

      outro = evento_em(DateTime.add(cancelado.starts_at, 60 * 60), %{title: "Ensaio geral"})
      event_band_fixture(%{event: outro, band: banda})

      {:ok, view, _html} =
        conn |> log_in_user(pastor_fixture()) |> live(~p"/events/#{cancelado.id}")

      html = render_click(view, "reopen")

      assert html =~ "#{banda.name} já está escalada em Ensaio geral, no mesmo horário."
      assert Schedule.get_event(cancelado.id).status == :cancelled
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

  describe "o link Montar set (US 3.6)" do
    setup do
      carla = member_fixture()
      ebenezer = banda_chamada("Banda Ebenezer", %{leader: carla})
      evento = event_fixture(%{title: "Culto da Noite"})
      event_band_fixture(%{event: evento, band: ebenezer})

      %{carla: carla, ebenezer: ebenezer, evento: evento}
    end

    test "o Líder da banda escalada monta o set dela", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer,
      evento: evento
    } do
      {:ok, view, _html} = conn |> log_in_user(carla) |> live(~p"/events/#{evento.id}")

      assert has_element?(
               view,
               "#manage-set-#{ebenezer.id}[href=\"/events/#{evento.id}/bands/#{ebenezer.id}/set\"]"
             )
    end

    test "quem tem acesso total monta o de qualquer banda", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      {:ok, view, _html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#manage-set-#{ebenezer.id}")
    end

    # A pergunta do set é mais estreita do que a de editar o evento: o líder de
    # outra banda escalada mexe no culto e não no set alheio.
    test "o Líder de outra banda escalada não vê o link desta", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      outro_lider = member_fixture()
      sion = banda_chamada("Banda Sion", %{leader: outro_lider})
      event_band_fixture(%{event: evento, band: sion})

      {:ok, view, _html} = conn |> log_in_user(outro_lider) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#manage-set-#{sion.id}")
      refute has_element?(view, "#manage-set-#{ebenezer.id}")
    end

    test "o músico comum não vê link nenhum", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      musico = member_fixture()
      band_member_fixture(%{band: ebenezer, user: musico})

      {:ok, view, _html} = conn |> log_in_user(musico) |> live(~p"/events/#{evento.id}")

      refute has_element?(view, "#manage-set-#{ebenezer.id}")
    end
  end

  describe "o set de cada banda (US 3.7)" do
    setup do
      carla = member_fixture()
      ebenezer = banda_chamada("Banda Ebenezer", %{leader: carla})
      evento = event_fixture(%{title: "Culto da Noite"})
      escala = event_band_fixture(%{event: evento, band: ebenezer})

      %{carla: carla, ebenezer: ebenezer, evento: evento, escala: escala}
    end

    test "o músico da banda vê o set dela na ordem", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      musico = member_fixture()
      band_member_fixture(%{band: ebenezer, user: musico})
      no_set(escala, ebenezer, "Santo", 2)
      no_set(escala, ebenezer, "Aleluia", 1)

      {:ok, _view, html} = conn |> log_in_user(musico) |> live(~p"/events/#{evento.id}")

      [a, s] = posicoes(html, ["Aleluia", "Santo"])
      assert a < s
    end

    # Ver o set alheio é leitura ampla: quem não toca também tem interesse
    # legítimo — o pastor, quem opera o som, quem vai cantar junto.
    test "o músico de outra banda vê o mesmo", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      no_set(escala, ebenezer, "Aleluia", 1)

      {:ok, _view, html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert html =~ "Aleluia"
    end

    test "a banda que ainda não montou diz que não montou", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-set-empty-#{ebenezer.id}", "Set ainda não montado.")
      refute has_element?(view, "#event-band-set-#{ebenezer.id}")
    end

    test "duas bandas escaladas mostram dois sets, cada um na sua ordem", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: evento, band: sion})

      no_set(escala, ebenezer, "Aleluia", 1)
      no_set(outra, sion, "Grande é o Senhor", 1)

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-set-#{ebenezer.id}", "Aleluia")
      assert has_element?(view, "#event-band-set-#{sion.id}", "Grande é o Senhor")
      refute has_element?(view, "#event-band-set-#{ebenezer.id}", "Grande é o Senhor")
    end

    test "o item sem tom próprio mostra o tom da banda", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      item = no_set(escala, ebenezer, "Aleluia", 1, key_da_banda: "D")

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#set-key-#{item.id}", "D")
      assert has_element?(view, "#set-key-note-#{item.id}", "Tom da banda: D")
    end

    test "o tom deste evento passa a valer, sem esconder o da banda", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      item = no_set(escala, ebenezer, "Aleluia", 1, key_da_banda: "D", key: "C")

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#set-key-#{item.id}", "C")
      assert has_element?(view, "#set-key-note-#{item.id}", "Só deste evento · a banda toca em D")
    end

    # A trava do repertório só segura evento futuro, então a música pode ter
    # saído da banda depois de entrar no set.
    test "a música fora do repertório mostra travessão e diz por quê", %{
      conn: conn,
      escala: escala,
      evento: evento
    } do
      item = event_band_song_fixture(%{event_band: escala, song: song_fixture(title: "Aleluia")})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#set-key-#{item.id}", "—")
      assert has_element?(view, "#set-key-note-#{item.id}", "Fora do repertório da banda")
    end

    test "a cifra e a referência aparecem na linha", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      entry =
        band_repertoire_fixture(%{
          band: ebenezer,
          song:
            song_fixture(
              title: "Aleluia",
              chord_chart_url: "https://cifras.example/aleluia",
              reference_url: "https://video.example/aleluia"
            )
        })

      item = event_band_song_fixture(%{event_band: escala, song: entry.song})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(
               view,
               "#set-chord-chart-#{item.id}[href=\"https://cifras.example/aleluia\"][target=_blank]"
             )

      assert has_element?(view, "#set-reference-#{item.id}[target=_blank]")
    end

    test "a música sem link nenhum não mostra nada no lugar deles", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      item = no_set(escala, ebenezer, "Aleluia", 1)

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      refute has_element?(view, "#set-chord-chart-#{item.id}")
      refute has_element?(view, "#set-reference-#{item.id}")
    end

    # A ordem é informação, não controle: quem lê o set aqui não arrasta nada.
    test "a linha da tela do evento não tem alça nem controles", %{
      conn: conn,
      ebenezer: ebenezer,
      escala: escala,
      evento: evento
    } do
      item = no_set(escala, ebenezer, "Aleluia", 1)

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      refute has_element?(view, "#set-song-#{item.id}[draggable]")
      refute has_element?(view, "#set-event-key-#{item.id}")
      refute has_element?(view, "#remove-set-song-#{item.id}")
    end
  end

  describe "o elenco de cada banda (US 4.1)" do
    setup do
      carla = member_fixture(%{name: "Carla Líder"})
      ebenezer = banda_chamada("Banda Ebenezer", %{leader: carla})
      band_member_fixture(%{band: ebenezer, user: carla, instrument: "Violão"})
      evento = event_fixture(%{title: "Culto da Noite"})
      escala = event_band_fixture(%{event: evento, band: ebenezer})

      %{carla: carla, ebenezer: ebenezer, evento: evento, escala: escala}
    end

    test "o músico comum vê quem toca na banda escalada, com a função de cada um", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer,
      evento: evento
    } do
      ana = member_fixture(%{name: "Ana Tecladista"})
      band_member_fixture(%{band: ebenezer, user: ana, instrument: "Teclado"})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{carla.id}", "Violão")
      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{ana.id}", "Ana Tecladista")
      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{ana.id}", "Teclado")
    end

    test "o vocalista aparece com o naipe dele", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      bruna = member_fixture(%{name: "Bruna Vocal"})

      band_member_fixture(%{
        band: ebenezer,
        user: bruna,
        type: :vocalist,
        voice_part: "Soprano"
      })

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{bruna.id}", "Vocal — Soprano")
    end

    test "duas bandas escaladas mostram dois elencos, cada um sob a sua banda", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer,
      evento: evento
    } do
      sion = banda_chamada("Banda Sion")
      event_band_fixture(%{event: evento, band: sion})
      diego = member_fixture(%{name: "Diego Baixista"})
      band_member_fixture(%{band: sion, user: diego, instrument: "Baixo"})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-roster-#{ebenezer.id}", "Carla Líder")
      assert has_element?(view, "#event-band-roster-#{sion.id}", "Diego Baixista")
      refute has_element?(view, "#event-band-roster-#{ebenezer.id}", "Diego Baixista")
      refute has_element?(view, "#roster-entry-#{ebenezer.id}-#{diego.id}")
      refute has_element?(view, "#roster-entry-#{sion.id}-#{carla.id}")

      # O par do `refute` do evento sem escala: o seletor por prefixo encontra
      # elenco quando há elenco, então lá ele prova ausência de verdade.
      assert has_element?(view, "[id^='event-band-roster-']")
    end

    test "o líder que toca aparece uma vez só, no topo, com a marca Líder", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer,
      evento: evento
    } do
      ana = member_fixture(%{name: "Ana Tecladista"})
      band_member_fixture(%{band: ebenezer, user: ana, instrument: "Teclado"})

      {:ok, view, html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{carla.id}", "Líder")

      # Uma linha só para ela: o líder com vínculo não se repete como membro.
      assert length(:binary.matches(html, "roster-entry-#{ebenezer.id}-#{carla.id}")) == 1

      [carla_em, ana_em] = posicoes(html, ["Carla Líder", "Ana Tecladista"])
      assert carla_em < ana_em
    end

    test "o líder sem vínculo abre o elenco cobrando a função", %{conn: conn} do
      sofia = member_fixture(%{name: "Sofia Tecladista"})
      banda_b = banda_chamada("Banda B", %{leader: sofia})
      evento = event_fixture()
      event_band_fixture(%{event: evento, band: banda_b})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(
               view,
               "#roster-entry-#{banda_b.id}-#{sofia.id}",
               "Sem função definida"
             )
    end

    test "os instrumentistas vêm antes dos vocalistas, e o nome desempata", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      band_member_fixture(%{
        band: ebenezer,
        user: member_fixture(%{name: "Bruna Vocal"}),
        type: :vocalist,
        voice_part: "Soprano"
      })

      band_member_fixture(%{band: ebenezer, user: member_fixture(%{name: "Zeca Baterista"})})
      band_member_fixture(%{band: ebenezer, user: member_fixture(%{name: "Diego Baixista"})})

      {:ok, _view, html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      lugares = posicoes(html, ["Carla Líder", "Diego Baixista", "Zeca Baterista", "Bruna Vocal"])

      assert lugares == Enum.sort(lugares)
    end

    test "o músico comum não ganha botão nenhum sobre o elenco", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-roster-#{ebenezer.id}")
      refute has_element?(view, "#event-band-roster-#{ebenezer.id} button")
      refute has_element?(view, "#event-band-roster-#{ebenezer.id} a")
    end

    test "o evento sem banda escalada não tem elenco nenhum", %{conn: conn} do
      evento = event_fixture()

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-bands-empty", "Nenhuma banda escalada.")
      refute has_element?(view, "[id^='event-band-roster-']")
    end

    test "o evento cancelado continua mostrando o elenco", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer,
      evento: evento
    } do
      {:ok, _evento} = Schedule.cancel_event(evento)

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-cancelled-badge")
      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{carla.id}", "Carla Líder")
    end

    # O elenco é derivado de `band_members`: quem sai da banda some do evento,
    # sem ninguém precisar mexer na escala.
    test "quem é removido da banda some do elenco do evento", %{
      conn: conn,
      ebenezer: ebenezer,
      evento: evento
    } do
      ana = member_fixture(%{name: "Ana Tecladista"})
      vinculo = band_member_fixture(%{band: ebenezer, user: ana, instrument: "Teclado"})
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")
      assert has_element?(view, "#roster-entry-#{ebenezer.id}-#{ana.id}")

      {:ok, _vinculo} = Bands.remove_member(vinculo)

      {:ok, view, _html} = live(conn, ~p"/events/#{evento.id}")
      refute has_element?(view, "#roster-entry-#{ebenezer.id}-#{ana.id}")
    end
  end

  describe "o botão Solicitar troca (US 4.2)" do
    # O cenário dos seeds: o Elias toca guitarra na Banda A, que tem o "Culto
    # da Noite"; a Banda B, liderada pela Sofia **sem vínculo**, tem o "Culto da
    # Manhã" com o Rafael na guitarra, a Júlia no soprano e o Lucas no baixo.
    setup %{conn: conn} do
      elias = member_fixture(%{name: "Elias Guitarrista"})
      rafael = member_fixture(%{name: "Rafael Guitarrista"})
      julia = member_fixture(%{name: "Júlia Vocalista"})
      lucas = member_fixture(%{name: "Lucas Vocalista"})
      sofia = member_fixture(%{name: "Sofia Tecladista"})

      banda_a = banda_chamada("Banda A")
      banda_b = banda_chamada("Banda B", %{leader: sofia})

      culto_noite = evento_em(in_days(3), %{title: "Culto da Noite"})
      culto_manha = evento_em(in_days(4), %{title: "Culto da Manhã"})

      %{
        conn: conn,
        elias: elias,
        rafael: rafael,
        sofia: sofia,
        banda_a: banda_a,
        banda_b: banda_b,
        culto_noite: culto_noite,
        culto_manha: culto_manha,
        elias_a: band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"}),
        rafael_b: band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"}),
        julia_b:
          band_member_fixture(%{
            band: banda_b,
            user: julia,
            type: :vocalist,
            voice_part: "Soprano"
          }),
        lucas_b:
          band_member_fixture(%{band: banda_b, user: lucas, type: :vocalist, voice_part: "Baixo"}),
        escala_a: event_band_fixture(%{event: culto_noite, band: banda_a}),
        escala_b: event_band_fixture(%{event: culto_manha, band: banda_b})
      }
    end

    test "aparece sobre quem faz a mesma função, e sobre mais ninguém", ctx do
      {:ok, view, _html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{ctx.culto_manha.id}")

      assert element(view, "#request-swap-#{ctx.rafael_b.id}") |> render() =~
               "/events/#{ctx.culto_manha.id}/members/#{ctx.rafael_b.id}/swap"

      refute has_element?(view, "#request-swap-#{ctx.julia_b.id}")
      refute has_element?(view, "#request-swap-#{ctx.lucas_b.id}")
    end

    test "a vocalista soprano só o vê nas sopranos das outras bandas", ctx do
      gabriela = member_fixture(%{name: "Gabriela Vocalista"})

      band_member_fixture(%{
        band: ctx.banda_a,
        user: gabriela,
        type: :vocalist,
        voice_part: "Soprano"
      })

      {:ok, view, _html} =
        ctx.conn |> log_in_user(gabriela) |> live(~p"/events/#{ctx.culto_manha.id}")

      assert has_element?(view, "#request-swap-#{ctx.julia_b.id}")
      refute has_element?(view, "#request-swap-#{ctx.lucas_b.id}")
      refute has_element?(view, "#request-swap-#{ctx.rafael_b.id}")
    end

    test "o Líder de Banda sem vínculo não é alvo: ele nem tem linha com id de vínculo", ctx do
      {:ok, view, html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{ctx.culto_manha.id}")

      assert html =~ "Sem função definida"
      assert has_element?(view, "#roster-entry-#{ctx.banda_b.id}-#{ctx.sofia.id}")
      assert Enum.count(String.split(html, "Solicitar troca")) == 2
    end

    test "não aparece no próprio nome", ctx do
      {:ok, view, _html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{ctx.culto_noite.id}")

      refute has_element?(view, "#request-swap-#{ctx.elias_a.id}")
    end

    test "não aparece em quem já está escalado no seu evento", ctx do
      # A Banda B passa a tocar também no "Culto da Noite": o Rafael vai estar
      # lá de qualquer jeito, e pedir troca com ele deixaria a banda sem
      # guitarra do mesmo jeito.
      event_band_fixture(%{event: ctx.culto_noite, band: ctx.banda_b})

      {:ok, view, _html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{ctx.culto_manha.id}")

      refute has_element?(view, "#request-swap-#{ctx.rafael_b.id}")
    end

    test "não aparece em evento cancelado nem em evento que já passou", ctx do
      {:ok, cancelado} = Schedule.cancel_event(ctx.culto_manha)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{cancelado.id}")
      refute has_element?(view, "#request-swap-#{ctx.rafael_b.id}")

      passado = evento_em(in_days(-3), %{title: "Culto passado"})
      event_band_fixture(%{event: passado, band: ctx.banda_b})

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{passado.id}")
      refute has_element?(view, "#request-swap-#{ctx.rafael_b.id}")
    end

    test "quem não está escalado em evento futuro nenhum não vê botão nenhum", ctx do
      {:ok, _} = Schedule.cancel_event(ctx.culto_noite)

      {:ok, view, html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/events/#{ctx.culto_manha.id}")

      refute has_element?(view, "#request-swap-#{ctx.rafael_b.id}")
      refute html =~ "Solicitar troca"
    end

    test "quem não toca em banda nenhuma continua lendo o elenco sem botão", ctx do
      {:ok, view, html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_manha.id}")

      assert has_element?(view, "#roster-entry-#{ctx.banda_b.id}-#{ctx.rafael.id}")
      refute html =~ "Solicitar troca"
    end
  end

  describe "a vaga trocada no elenco (US 4.3)" do
    # O Elias pediu troca ao Rafael e ele aceitou. O que muda no elenco de cada
    # evento é o que esta seção verifica — e nada em `band_members` muda.
    setup %{conn: conn} do
      elias = member_fixture(%{name: "Elias Guitarrista"})
      rafael = member_fixture(%{name: "Rafael Guitarrista"})
      marcos = member_fixture(%{name: "Marcos Baixista"})

      banda_a = banda_chamada("Banda A")
      banda_b = banda_chamada("Banda B")

      culto_noite = evento_em(in_days(3), %{title: "Culto da Noite"})
      culto_manha = evento_em(in_days(4), %{title: "Culto da Manhã"})

      escala_a = event_band_fixture(%{event: culto_noite, band: banda_a})
      escala_b = event_band_fixture(%{event: culto_manha, band: banda_b})

      elias_a = band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"})
      rafael_b = band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"})
      band_member_fixture(%{band: banda_a, user: marcos, instrument: "Baixo"})

      %{
        conn: conn,
        elias: elias,
        rafael: rafael,
        marcos: marcos,
        banda_a: banda_a,
        banda_b: banda_b,
        culto_noite: culto_noite,
        culto_manha: culto_manha,
        escala_a: escala_a,
        escala_b: escala_b,
        elias_a: elias_a,
        rafael_b: rafael_b
      }
    end

    test "o substituto ocupa a vaga do titular, com a marca e o no lugar de", ctx do
      trocar(ctx, :cover)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_noite.id}")

      linha = view |> element("#roster-entry-#{ctx.banda_a.id}-#{ctx.elias.id}") |> render()

      assert linha =~ "Rafael Guitarrista"
      assert linha =~ "no lugar de Elias Guitarrista"
      assert linha =~ "Provisório"
      assert has_element?(view, "#roster-provisional-#{ctx.banda_a.id}-#{ctx.elias.id}")
    end

    test "em só cobrir, o evento do alvo continua como estava", ctx do
      trocar(ctx, :cover)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_manha.id}")

      refute has_element?(view, "#roster-provisional-#{ctx.banda_b.id}-#{ctx.rafael.id}")

      assert view |> element("#roster-entry-#{ctx.banda_b.id}-#{ctx.rafael.id}") |> render() =~
               "Rafael Guitarrista"
    end

    test "em trocar o dia, cada evento mostra o outro na vaga", ctx do
      trocar(ctx, :swap)

      {:ok, noite, _} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_noite.id}")

      assert noite |> element("#roster-entry-#{ctx.banda_a.id}-#{ctx.elias.id}") |> render() =~
               "Rafael Guitarrista"

      {:ok, manha, _} =
        build_conn() |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_manha.id}")

      linha = manha |> element("#roster-entry-#{ctx.banda_b.id}-#{ctx.rafael.id}") |> render()

      assert linha =~ "Elias Guitarrista"
      assert linha =~ "no lugar de Rafael Guitarrista"
    end

    test "a ordem do elenco continua sendo a da vaga", ctx do
      trocar(ctx, :cover)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_noite.id}")

      html = view |> element("#event-band-roster-#{ctx.banda_a.id}") |> render()

      # O elenco se ordena pelo nome do **titular**: Elias vem antes de Marcos.
      # Fosse pelo nome de quem aparece, Marcos viria antes de Rafael — e é
      # essa a diferença que o teste separa.
      assert :binary.match(html, "Rafael Guitarrista") < :binary.match(html, "Marcos Baixista")
    end

    test "a vaga trocada não recebe outro pedido: o botão some dela", ctx do
      trocar(ctx, :cover)

      gabriela = member_fixture(%{name: "Gabriela Guitarrista"})
      banda_c = banda_chamada("Banda C")
      band_member_fixture(%{band: banda_c, user: gabriela, instrument: "Guitarra"})
      event_band_fixture(%{event: evento_em(in_days(6), %{}), band: banda_c})

      {:ok, view, _html} =
        ctx.conn |> log_in_user(gabriela) |> live(~p"/events/#{ctx.culto_noite.id}")

      refute has_element?(view, "#request-swap-#{ctx.elias_a.id}")
    end

    test "o evento cancelado continua mostrando a troca aceita", ctx do
      trocar(ctx, :cover)
      {:ok, _} = Schedule.cancel_event(ctx.culto_noite)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_noite.id}")

      assert has_element?(view, "#roster-provisional-#{ctx.banda_a.id}-#{ctx.elias.id}")
    end

    test "desescalar a banda de origem desfaz a troca no outro evento", ctx do
      trocar(ctx, :swap)
      {:ok, _} = Schedule.unschedule_band(ctx.escala_a)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/events/#{ctx.culto_manha.id}")

      refute has_element?(view, "#roster-provisional-#{ctx.banda_b.id}-#{ctx.rafael.id}")
    end

    test "o elenco da banda, em /bands/:id, fica intacto: a troca é do evento", ctx do
      trocar(ctx, :swap)

      {:ok, view, _html} =
        ctx.conn |> log_in_user(member_fixture()) |> live(~p"/bands/#{ctx.banda_a.id}")

      assert render(view) =~ "Elias Guitarrista"
      refute render(view) =~ "Provisório"
    end

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

  describe "tempo real (#112)" do
    test "escalar uma banda aparece sozinho para quem está com o evento aberto", %{conn: conn} do
      evento = event_fixture()
      banda = banda_chamada("Banda Ebenezer")

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-bands-empty")

      {:ok, _event_band} = Schedule.schedule_band(evento, banda.id)

      refute has_element?(view, "#event-bands-empty")
      assert has_element?(view, "#event-band-#{banda.id}")
    end

    test "desescalar tira a banda do bloco sozinho, sem F5", %{conn: conn} do
      evento = event_fixture()
      banda = banda_chamada("Banda Ebenezer")
      escala = event_band_fixture(%{event: evento, band: banda})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-#{banda.id}")

      {:ok, _} = Schedule.unschedule_band(escala)

      refute has_element?(view, "#event-band-#{banda.id}")
      assert has_element?(view, "#event-bands-empty")
    end

    test "uma música entra no set e aparece sozinha para quem está com o evento aberto", %{
      conn: conn
    } do
      ebenezer = banda_chamada("Banda Ebenezer")
      evento = event_fixture(%{title: "Culto da Noite"})
      escala = event_band_fixture(%{event: evento, band: ebenezer})
      entry = band_repertoire_fixture(%{band: ebenezer, song: song_fixture(title: "Aleluia")})

      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      assert has_element?(view, "#event-band-set-empty-#{ebenezer.id}")

      {:ok, _item} = Schedule.add_song_to_set(escala, entry.song_id)

      refute has_element?(view, "#event-band-set-empty-#{ebenezer.id}")
      assert has_element?(view, "#event-band-set-#{ebenezer.id}", "Aleluia")
    end

    test "o aceite de uma troca põe o substituto no elenco sem F5", %{conn: conn} do
      elias = member_fixture(%{name: "Elias Guitarrista"})
      rafael = member_fixture(%{name: "Rafael Guitarrista"})

      banda_a = banda_chamada("Banda A")
      banda_b = banda_chamada("Banda B")

      culto_noite = evento_em(in_days(3), %{title: "Culto da Noite"})
      culto_manha = evento_em(in_days(4), %{title: "Culto da Manhã"})

      escala_a = event_band_fixture(%{event: culto_noite, band: banda_a})
      escala_b = event_band_fixture(%{event: culto_manha, band: banda_b})

      elias_a = band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"})
      rafael_b = band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"})

      pedido =
        swap_request_fixture(%{
          requester_event_band: escala_a,
          requester_member: elias_a,
          target_event_band: escala_b,
          target_member: rafael_b
        })

      {:ok, view, _html} =
        conn |> log_in_user(member_fixture()) |> live(~p"/events/#{culto_noite.id}")

      refute render(view) =~ "Provisório"

      {:ok, _accepted} =
        ChurchBands.Swaps.accept_request(
          rafael,
          ChurchBands.Swaps.get_request(pedido.id),
          "cover"
        )

      linha = view |> element("#roster-entry-#{banda_a.id}-#{elias.id}") |> render()
      assert linha =~ "Rafael Guitarrista"
      assert linha =~ "Provisório"
    end

    test "mensagem desconhecida no tópico do evento não derruba a view", %{conn: conn} do
      evento = event_fixture()
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/events/#{evento.id}")

      Phoenix.PubSub.broadcast(
        ChurchBands.PubSub,
        ChurchBands.Realtime.event_topic(evento),
        :uma_mensagem_que_ninguem_conhece
      )

      assert has_element?(view, "#event-bands-empty")
    end
  end
end
