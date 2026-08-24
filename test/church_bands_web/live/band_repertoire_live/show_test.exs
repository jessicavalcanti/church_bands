defmodule ChurchBandsWeb.BandRepertoireLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  defp repertoire_path(band), do: ~p"/bands/#{band.id}/repertoire"

  # A US 2.6 abriu esta tela: até a US 2.2 ela era inteira de quem monta o
  # repertório, e músico comum e Líder de outra banda eram recusados na porta.
  describe "quem lê o repertório" do
    test "o músico comum de outra banda vê a lista inteira", %{conn: conn} do
      band = band_fixture(%{name: "Banda Jovem"})
      song = song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})
      entry = band_repertoire_fixture(%{band: band, song: song, key: "D"})
      band_member_fixture(%{band: band_fixture(), user: musician = member_fixture()})

      {:ok, view, html} = live(log_in_user(conn, musician), repertoire_path(band))

      assert html =~ "Grande é o Senhor"
      assert html =~ "Adhemar de Campos"
      assert view |> element("#repertoire-key-#{entry.id}") |> render() =~ "D"
      assert view |> element("#repertoire-status-#{entry.id}") |> render() =~ "Em aprendizado"
    end

    test "o Líder da Banda Y lê o repertório da Banda X", %{conn: conn} do
      leader_y = member_fixture()
      band_fixture(%{leader: leader_y})
      banda_x = band_fixture()
      band_repertoire_fixture(%{band: banda_x, song: song_fixture(%{title: "Oceanos"})})

      {:ok, _view, html} = live(log_in_user(conn, leader_y), repertoire_path(banda_x))

      assert html =~ "Oceanos"
    end

    test "as tags e os links de cada música aparecem na linha", %{conn: conn} do
      band = band_fixture()
      tag = tag_fixture(%{name: "Vigília"})

      song =
        song_fixture(%{
          title: "Oceanos",
          tags: [tag],
          reference_url: "https://example.com/video",
          chord_chart_url: "https://example.com/cifra"
        })

      entry = band_repertoire_fixture(%{band: band, song: song})

      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      assert view |> element("#repertoire-tags-#{entry.id}") |> render() =~ "Vigília"

      assert view |> element("#repertoire-chord-chart-#{entry.id}") |> render() =~
               ~s(href="https://example.com/cifra")

      assert view |> element("#repertoire-chord-chart-#{entry.id}") |> render() =~
               ~s(target="_blank")

      assert has_element?(view, "#repertoire-reference-#{entry.id}")
    end

    test "música sem link e sem tag não mostra ícone nem badge", %{conn: conn} do
      band = band_fixture()
      entry = band_repertoire_fixture(%{band: band, song: song_fixture()})

      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      refute has_element?(view, "#repertoire-reference-#{entry.id}")
      refute has_element?(view, "#repertoire-chord-chart-#{entry.id}")
      refute has_element?(view, "#repertoire-tags-#{entry.id}")
    end

    test "as músicas saem em ordem alfabética de título", %{conn: conn} do
      band = band_fixture()

      for title <- ["Ressuscita-me", "Ágape", "Bondade de Deus"] do
        band_repertoire_fixture(%{band: band, song: song_fixture(%{title: title})})
      end

      {:ok, _view, html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      posicoes =
        Enum.map(["Ágape", "Bondade de Deus", "Ressuscita-me"], fn title ->
          html |> :binary.match(title) |> elem(0)
        end)

      assert posicoes == Enum.sort(posicoes)
    end

    test "o repertório de uma banda não mostra o da outra", %{conn: conn} do
      band = band_fixture()
      band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Só desta banda"})})

      band_repertoire_fixture(%{
        band: band_fixture(),
        song: song_fixture(%{title: "Só da outra banda"})
      })

      {:ok, _view, html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      assert html =~ "Só desta banda"
      refute html =~ "Só da outra banda"
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, repertoire_path(band_fixture()))

      assert flash["error"] == "Você precisa entrar para acessar esta página."
    end

    test "banda inexistente volta para a lista", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, member_fixture()), ~p"/bands/0/repertoire")

      assert flash["error"] == "Banda não encontrada."
    end
  end

  describe "quem monta o repertório" do
    test "o Líder da banda, o Pastor e o Líder de Louvor veem Adicionar música", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      for user <- [leader, pastor_fixture(), worship_leader_fixture()] do
        {:ok, view, _html} = live(log_in_user(conn, user), repertoire_path(band))

        assert has_element?(view, "#add-repertoire-song")
      end
    end

    test "músico comum e Líder de outra banda não veem o botão", %{conn: conn} do
      leader_y = member_fixture()
      band_fixture(%{leader: leader_y})
      banda_x = band_fixture()

      for user <- [member_fixture(), leader_y] do
        {:ok, view, _html} = live(log_in_user(conn, user), repertoire_path(banda_x))

        assert has_element?(view, "#repertoire-empty")
        refute has_element?(view, "#add-repertoire-song")
      end
    end

    test "forçar o formulário de vínculo continua sendo recusado", %{conn: conn} do
      band = band_fixture()

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, member_fixture()), ~p"/bands/#{band.id}/repertoire/new")

      assert flash["error"] == "Você não tem permissão para gerenciar o repertório desta banda."
    end

    test "o botão leva ao formulário de vínculo", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      assert view |> element("#add-repertoire-song") |> render_click() ==
               {:error, {:live_redirect, %{kind: :push, to: "/bands/#{band.id}/repertoire/new"}}}
    end
  end

  describe "filtro por status na tela" do
    setup %{conn: conn} do
      band = band_fixture()

      for status <- [:learning, :ready, :archived] do
        song = song_fixture(%{title: "Música #{status}"})
        band_repertoire_fixture(%{band: band, song: song, status: status})
      end

      %{conn: log_in_user(conn, member_fixture()), band: band}
    end

    test "sem filtrar, a arquivada não aparece", %{conn: conn, band: band} do
      {:ok, view, html} = live(conn, repertoire_path(band))

      assert html =~ "Música learning"
      assert html =~ "Música ready"
      refute html =~ "Música archived"
      assert has_element?(view, "#filter-status-learning[aria-pressed='false']")
    end

    test "clicar em Arquivada mostra só as arquivadas e marca o badge", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      html = view |> element("#filter-status-archived") |> render_click()

      assert html =~ "Música archived"
      refute html =~ "Música learning"
      assert has_element?(view, "#filter-status-archived[aria-pressed='true']")
      assert_patch(view, "/bands/#{band.id}/repertoire?status=archived")
    end

    test "Todas mostra as arquivadas junto com as demais", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      html = view |> element("#filter-status-all") |> render_click()

      assert html =~ "Música learning"
      assert html =~ "Música ready"
      assert html =~ "Música archived"
    end

    test "clicar de novo no badge marcado volta ao padrão", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      view |> element("#filter-status-learning") |> render_click()
      assert has_element?(view, "#filter-status-learning[aria-pressed='true']")

      html = view |> element("#filter-status-learning") |> render_click()

      assert html =~ "Música ready"
      assert has_element?(view, "#filter-status-learning[aria-pressed='false']")
      assert_patch(view, "/bands/#{band.id}/repertoire")
    end

    test "status desconhecido na URL cai no padrão, sem erro", %{conn: conn, band: band} do
      {:ok, view, html} = live(conn, repertoire_path(band) <> "?status=xyz")

      assert html =~ "Música learning"
      refute html =~ "Música archived"

      for status <- ~w(learning ready archived all) do
        assert has_element?(view, "#filter-status-#{status}[aria-pressed='false']")
      end
    end
  end

  describe "busca na tela" do
    setup %{conn: conn} do
      band = band_fixture()

      band_repertoire_fixture(%{
        band: band,
        song: song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})
      })

      band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Oceanos"})})

      %{conn: log_in_user(conn, member_fixture()), band: band}
    end

    test "estreita a lista pelo que foi digitado", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      html =
        view
        |> form("#repertoire-search-form", %{"busca" => "senhor"})
        |> render_change()

      assert html =~ "Grande é o Senhor"
      refute html =~ "Oceanos"
      assert_patch(view, "/bands/#{band.id}/repertoire?busca=senhor")
    end

    test "a busca não vaza para o catálogo", %{conn: conn, band: band} do
      song_fixture(%{title: "Ousado Amor"})

      {:ok, view, _html} = live(conn, repertoire_path(band))

      html = view |> form("#repertoire-search-form", %{"busca" => "ousado"}) |> render_change()

      assert html =~ "Nenhuma música encontrada."
      refute html =~ "Ousado Amor"
    end

    test "acha mesmo sem acento e com erro de digitação", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      html =
        view
        |> form("#repertoire-search-form", %{"busca" => "Grande e o Senhôr"})
        |> render_change()

      assert html =~ "Grande é o Senhor"
    end

    test "busca e status se combinam", %{conn: conn, band: band} do
      arquivada = song_fixture(%{title: "Senhor, eu preciso de ti"})
      band_repertoire_fixture(%{band: band, song: arquivada, status: :archived})

      {:ok, view, _html} = live(conn, repertoire_path(band) <> "?status=archived&busca=senhor")

      html = render(view)

      assert html =~ "Senhor, eu preciso de ti"
      refute html =~ "Grande é o Senhor"
      assert has_element?(view, "#filter-status-archived[aria-pressed='true']")
      assert has_element?(view, "input#repertoire-search[value='senhor']")
    end

    test "limpar busca e filtro devolve a lista inteira", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band) <> "?busca=zzzz&status=ready")

      assert has_element?(view, "#repertoire-not-found")

      html = view |> element("#clear-filters") |> render_click()

      assert html =~ "Grande é o Senhor"
      assert html =~ "Oceanos"
      assert_patch(view, "/bands/#{band.id}/repertoire")
    end
  end

  describe "os dois estados vazios" do
    test "banda sem repertório convida quem pode a adicionar a primeira", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      {:ok, view, html} = live(log_in_user(conn, leader), repertoire_path(band))

      assert has_element?(view, "#repertoire-empty")
      assert html =~ "Nenhuma música no repertório ainda."
      assert html =~ "Use <strong>Adicionar música</strong>"
      refute has_element?(view, "#repertoire-not-found")
    end

    test "quem não pode adicionar é dito a quem pedir", %{conn: conn} do
      band = band_fixture()

      {:ok, _view, html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      assert html =~ "Nenhuma música no repertório ainda."
      assert html =~ "Quem monta o repertório é o Líder desta banda"
      refute html =~ "Use <strong>Adicionar música</strong>"
    end

    test "busca sem resultado diz outra coisa, e oferece limpar", %{conn: conn} do
      band = band_fixture()
      band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Oceanos"})})

      {:ok, view, html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      refute has_element?(view, "#repertoire-empty")
      refute html =~ "Nenhuma música encontrada."

      html = view |> form("#repertoire-search-form", %{"busca" => "zzzz"}) |> render_change()

      assert html =~ "Nenhuma música encontrada."
      refute html =~ "Nenhuma música no repertório ainda."
      assert has_element?(view, "#clear-filters")
    end
  end
end
