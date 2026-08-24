defmodule ChurchBandsWeb.InstrumentLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  defp members_path(band), do: ~p"/bands/#{band.id}/members/new"

  describe "autorização de acesso" do
    test "Pastor acessa o catálogo", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/instruments")
      assert has_element?(view, "#new-instrument-button")
    end

    test "Líder de Louvor acessa o catálogo", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/instruments")
      assert has_element?(view, "#new-instrument-button")
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/instruments")
      assert flash["error"] =~ "não tem permissão"
    end

    # Liderar uma banda dá poder sobre o elenco dela, não sobre o catálogo do
    # grupo de louvor inteiro.
    test "Líder de Banda tem o acesso negado", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/instruments")
      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/instruments")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "a lista do catálogo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "os onze iniciais aparecem em ordem alfabética", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/instruments")

      posicoes =
        for nome <- ~w(Baixo Bateria Flauta Guitarra Percussão Piano Saxofone Teclado Trompete
                       Violão Violino) do
          posicao = :binary.match(html, nome)
          assert posicao != :nomatch, "#{nome} não está na lista"
          posicao
        end

      assert posicoes == Enum.sort(posicoes)
    end

    test "cada linha diz quantos integrantes tocam o instrumento", %{conn: conn} do
      band = band_fixture()
      bateria = band_member_fixture(%{band: band, instrument: "Bateria"}).instrument_id
      band_member_fixture(%{band: band, instrument: "Bateria"})
      flauta = band_member_fixture(%{band: band, instrument: "Flauta"}).instrument_id
      trompete = instrument_fixture("Trompete")

      {:ok, view, _html} = live(conn, ~p"/instruments")

      assert view |> element("#instrument-members-#{bateria}") |> render() =~ "2 integrantes"
      assert view |> element("#instrument-members-#{flauta}") |> render() =~ "1 integrante"
      assert view |> element("#instrument-members-#{trompete.id}") |> render() =~ "Ninguém"
    end

    test "o instrumento desativado aparece marcado como inativo", %{conn: conn} do
      trompete = instrument_fixture("Trompete")
      {:ok, _} = Bands.set_instrument_active(trompete, false)

      {:ok, view, _html} = live(conn, ~p"/instruments")

      assert view |> element("#instrument-status-#{trompete.id}") |> render() =~ "Inativo"
    end
  end

  describe "cadastro de instrumento" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "cadastra e volta para a lista com o instrumento novo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments")

      view |> element("#new-instrument-button") |> render_click()
      assert has_element?(view, "#instrument-form")

      view |> form("#instrument-form", instrument: %{name: "Cajón"}) |> render_submit()

      html = render(view)
      assert html =~ "Instrumento Cajón cadastrado."
      assert html =~ "Cajón"
      refute has_element?(view, "#instrument-form")
    end

    test "o instrumento cadastrado aparece no formulário de integrante", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      {:ok, view, _html} = live(conn, ~p"/instruments/new")
      view |> form("#instrument-form", instrument: %{name: "Cajón"}) |> render_submit()

      {:ok, member_view, _html} = live(log_in_user(build_conn(), leader), members_path(band))

      member_view
      |> form("#member-form", band_member: %{type: "instrumentalist"})
      |> render_change()

      assert member_view |> element("#band_member_instrument_id") |> render() =~ "Cajón"
    end

    test "recusa nome já cadastrado, sem distinguir maiúsculas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments/new")

      html = view |> form("#instrument-form", instrument: %{name: "bateria"}) |> render_submit()

      assert html =~ "já existe um instrumento com esse nome"
    end

    test "recusa nome curto demais", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments/new")

      html = view |> form("#instrument-form", instrument: %{name: "a"}) |> render_submit()

      assert html =~ "precisa ter entre 2 e 60 caracteres"
    end

    test "o erro aparece enquanto se digita, antes de enviar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments/new")

      html = view |> form("#instrument-form", instrument: %{name: "a"}) |> render_change()

      assert html =~ "precisa ter entre 2 e 60 caracteres"
    end

    test "cancelar fecha o formulário sem cadastrar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments/new")

      view |> element("#cancel-instrument-form") |> render_click()

      refute has_element?(view, "#instrument-form")
    end
  end

  describe "renomear instrumento" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "renomear vale para quem já toca o instrumento", %{conn: conn} do
      band = band_fixture()
      member = band_member_fixture(%{band: band, instrument: "Teclado"})

      {:ok, view, _html} = live(conn, ~p"/instruments")
      view |> element("#edit-instrument-#{member.instrument_id}") |> render_click()

      view
      |> form("#instrument-form", instrument: %{name: "Teclado 88 teclas"})
      |> render_submit()

      assert render(view) =~ "Instrumento Teclado 88 teclas atualizado."

      {:ok, _show, html} = live(conn, ~p"/bands/#{band.id}")
      assert html =~ "Teclado 88 teclas"
    end

    test "recusa renomear para um nome que já existe", %{conn: conn} do
      piano = instrument_fixture("Piano")

      {:ok, view, _html} = live(conn, ~p"/instruments/#{piano.id}/edit")

      html = view |> form("#instrument-form", instrument: %{name: "bateria"}) |> render_submit()

      assert html =~ "já existe um instrumento com esse nome"
    end

    test "instrumento inexistente devolve para a lista com o recado", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/instruments", flash: flash}}} =
               live(conn, ~p"/instruments/0/edit")

      assert flash["error"] =~ "Instrumento não encontrado."

      {:ok, view, _html} = live(conn, ~p"/instruments")
      refute has_element?(view, "#instrument-form")
    end
  end

  describe "desativar e reativar" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "desativar tira o instrumento do formulário de integrante sem mexer em quem já o toca",
         %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      member = band_member_fixture(%{band: band, instrument: "Trompete"})

      {:ok, view, _html} = live(conn, ~p"/instruments")
      view |> element("#toggle-instrument-#{member.instrument_id}") |> render_click()

      assert render(view) =~ "Instrumento Trompete desativado."

      assert view |> element("#instrument-status-#{member.instrument_id}") |> render() =~
               "Inativo"

      # A contagem continua certa depois de desativar: quem toca não mudou.
      assert view |> element("#instrument-members-#{member.instrument_id}") |> render() =~
               "1 integrante"

      # No elenco, a função de quem já tocava continua escrita.
      {:ok, _show, html} = live(conn, ~p"/bands/#{band.id}")
      assert html =~ "Trompete"

      # Mas ele deixa de ser oferecido para um vínculo novo.
      {:ok, member_view, _html} = live(log_in_user(build_conn(), leader), members_path(band))

      member_view
      |> form("#member-form", band_member: %{type: "instrumentalist"})
      |> render_change()

      refute member_view |> element("#band_member_instrument_id") |> render() =~ "Trompete"
    end

    test "reativar devolve o instrumento à lista de escolha", %{conn: conn} do
      trompete = instrument_fixture("Trompete")
      {:ok, _} = Bands.set_instrument_active(trompete, false)

      {:ok, view, _html} = live(conn, ~p"/instruments")
      view |> element("#toggle-instrument-#{trompete.id}") |> render_click()

      assert render(view) =~ "Instrumento Trompete reativado."
      assert view |> element("#instrument-status-#{trompete.id}") |> render() =~ "Ativo"
    end

    test "instrumento que sumiu do banco refaz a lista em vez de estourar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments")

      html = render_click(view, "toggle_active", %{"id" => "0"})

      assert html =~ "Instrumento não encontrado."
    end
  end

  describe "excluir instrumento" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "exclui o instrumento que ninguém toca", %{conn: conn} do
      cajon = instrument_fixture("Cajón")

      {:ok, view, _html} = live(conn, ~p"/instruments")
      view |> element("#delete-instrument-#{cajon.id}") |> render_click()

      assert render(view) =~ "Instrumento Cajón excluído."
      refute has_element?(view, "#delete-instrument-#{cajon.id}")
      assert Bands.get_instrument(cajon.id) == nil
    end

    test "a exclusão pede confirmação, dizendo qual instrumento", %{conn: conn} do
      cajon = instrument_fixture("Cajón")

      {:ok, view, _html} = live(conn, ~p"/instruments")

      assert view |> element("#delete-instrument-#{cajon.id}") |> render() =~
               "Excluir o instrumento Cajón?"
    end

    test "recusa excluir instrumento em uso, apontando desativar", %{conn: conn} do
      band = band_fixture()
      member = band_member_fixture(%{band: band, instrument: "Bateria"})
      band_member_fixture(%{band: band_fixture(), instrument: "Bateria"})

      {:ok, view, _html} = live(conn, ~p"/instruments")
      html = view |> element("#delete-instrument-#{member.instrument_id}") |> render_click()

      assert html =~ "Bateria é tocado por 2 integrantes."
      assert html =~ "Desative o instrumento em vez de excluí-lo."
      assert Bands.get_instrument(member.instrument_id)
    end

    test "instrumento que sumiu do banco refaz a lista em vez de estourar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/instruments")

      html = render_click(view, "delete", %{"id" => "0"})

      assert html =~ "Instrumento não encontrado."
    end
  end

  describe "a trilha da tela" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "a lista, o cadastro e a correção têm cada um a sua trilha", %{conn: conn} do
      cajon = instrument_fixture("Cajón")

      {:ok, _view, lista} = live(conn, ~p"/instruments")
      assert lista =~ "Instrumentos"

      {:ok, _view, cadastro} = live(conn, ~p"/instruments/new")
      assert cadastro =~ "Novo instrumento"

      {:ok, _view, correcao} = live(conn, ~p"/instruments/#{cajon.id}/edit")
      assert correcao =~ "Cajón"
    end
  end
end
