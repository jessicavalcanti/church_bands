defmodule ChurchBandsWeb.BandRepertoireLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Repertoire

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

  # A US 2.3 é a primeira escrita desta tela, e por isso é aqui que nasce a
  # reconferência de permissão no servidor: desde a US 2.6 qualquer usuário
  # logado tem a página na mão e pode disparar o evento pelo socket.
  describe "mudar tom e status na linha" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song, key: "D"})

      %{conn: conn, leader: leader, band: band, entry: entry}
    end

    test "o Líder da banda marca a música como pronta", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      html =
        view
        |> form("#repertoire-entry-#{entry.id}", %{"status" => "ready"})
        |> render_change()

      assert html =~ "Grande é o Senhor agora está pronta."
      assert Repertoire.get_band_song(entry.id).status == :ready
    end

    test "o Pastor faz o mesmo no repertório de qualquer banda", %{
      conn: conn,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), repertoire_path(band))

      html =
        view
        |> form("#repertoire-entry-#{entry.id}", %{"status" => "ready"})
        |> render_change()

      assert html =~ "Grande é o Senhor agora está pronta."
      assert Repertoire.get_band_song(entry.id).status == :ready
    end

    test "trocar o tom muda a linha e nomeia o tom novo", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      html = view |> form("#repertoire-entry-#{entry.id}", %{"key" => "C"}) |> render_change()

      assert html =~ "Grande é o Senhor agora está no tom C."

      assert view |> element("#repertoire-key-#{entry.id} option[selected]") |> render() =~ ">C<"
    end

    test "arquivar tira a linha da lista na hora, e o flash é o único sinal", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      html =
        view
        |> form("#repertoire-entry-#{entry.id}", %{"status" => "archived"})
        |> render_change()

      assert html =~ "Grande é o Senhor foi arquivada."
      refute has_element?(view, "#repertoire-entry-#{entry.id}")
      assert has_element?(view, "#repertoire-empty")
    end

    test "a arquivada aparece ao filtrar por Arquivada", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      view |> form("#repertoire-entry-#{entry.id}", %{"status" => "archived"}) |> render_change()
      html = view |> element("#filter-status-archived") |> render_click()

      assert html =~ "Grande é o Senhor"
    end

    test "de arquivada se volta para em aprendizado", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, _} = Repertoire.update_band_song(entry, %{"key" => "D", "status" => "archived"})

      {:ok, view, _html} =
        live(log_in_user(conn, leader), repertoire_path(band) <> "?status=archived")

      html =
        view
        |> form("#repertoire-entry-#{entry.id}", %{"status" => "learning"})
        |> render_change()

      assert html =~ "Grande é o Senhor voltou para em aprendizado."
      assert Repertoire.get_band_song(entry.id).status == :learning
    end

    test "a lista recarrega com o filtro e a busca que estavam valendo", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, _} = Repertoire.update_band_song(entry, %{"key" => "D", "status" => "ready"})
      outra = song_fixture(%{title: "Oceanos"})
      band_repertoire_fixture(%{band: band, song: outra, status: :learning})

      {:ok, view, _html} =
        live(log_in_user(conn, leader), repertoire_path(band) <> "?status=ready")

      html = view |> form("#repertoire-entry-#{entry.id}", %{"key" => "C"}) |> render_change()

      assert html =~ "Grande é o Senhor"
      refute html =~ "Oceanos"
      assert has_element?(view, "#filter-status-ready[aria-pressed='true']")
    end
  end

  describe "quem não pode alterar o repertório" do
    setup %{conn: conn} do
      band = band_fixture(%{name: "Banda X"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song, key: "D", status: :learning})

      %{conn: conn, band: band, entry: entry}
    end

    test "o músico comum vê tom e status como texto, sem seletor", %{
      conn: conn,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      assert view |> element("span#repertoire-key-#{entry.id}") |> render() =~ "D"
      assert view |> element("#repertoire-status-#{entry.id}") |> render() =~ "Em aprendizado"
      refute has_element?(view, "#repertoire-entry-#{entry.id}")
      refute has_element?(view, "select#repertoire-key-#{entry.id}")
    end

    test "o músico comum que dispara o evento pelo socket é recusado", %{
      conn: conn,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      html = update_event(view, entry, %{"status" => "ready"})

      assert html =~ "Você não tem permissão para alterar o repertório desta banda."
      assert Repertoire.get_band_song(entry.id).status == :learning
    end

    test "o Líder da Banda Y é recusado no repertório da Banda X", %{
      conn: conn,
      band: banda_x,
      entry: entry
    } do
      leader_y = member_fixture()
      band_fixture(%{leader: leader_y, name: "Banda Y"})

      {:ok, view, _html} = live(log_in_user(conn, leader_y), repertoire_path(banda_x))

      html = update_event(view, entry, %{"status" => "ready"})

      assert html =~ "Você não tem permissão para alterar o repertório desta banda."
      assert Repertoire.get_band_song(entry.id).status == :learning
    end
  end

  describe "entrada forçada na alteração do repertório" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda X"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song, key: "D", status: :learning})

      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      %{view: view, entry: entry}
    end

    test "o vínculo do repertório de outra banda não é encontrado", %{view: view} do
      de_outra_banda = band_repertoire_fixture(%{key: "G"})

      html = update_event(view, de_outra_banda, %{"status" => "ready"})

      assert html =~ "Música não encontrada no repertório desta banda."
      assert Repertoire.get_band_song(de_outra_banda.id).status == :learning
    end

    test "o vínculo que não existe também não é encontrado", %{view: view} do
      html =
        render_change(view, "update_entry", %{
          "entry_id" => "0",
          "key" => "C",
          "status" => "ready"
        })

      assert html =~ "Música não encontrada no repertório desta banda."
    end

    test "um tom fora da lista de 24 é recusado, e nada muda", %{view: view, entry: entry} do
      html = update_event(view, entry, %{"key" => "H"})

      assert html =~ "Não foi possível atualizar a música."
      assert Repertoire.get_band_song(entry.id).key == :D
    end

    test "um status que não existe é recusado, e nada muda", %{view: view, entry: entry} do
      html = update_event(view, entry, %{"status" => "tocada"})

      assert html =~ "Não foi possível atualizar a música."
      assert Repertoire.get_band_song(entry.id).status == :learning
    end
  end

  # O evento mandado direto pelo socket, sem o controle na tela: é assim que se
  # prova que a proteção está no servidor, e não no `:if` do formulário.
  defp update_event(view, entry, params) do
    payload =
      Map.merge(
        %{
          "entry_id" => to_string(entry.id),
          "key" => to_string(entry.key),
          "status" => to_string(entry.status)
        },
        params
      )

    render_change(view, "update_entry", payload)
  end

  describe "remover música do repertório" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song})

      %{conn: conn, leader: leader, band: band, entry: entry}
    end

    test "o Líder da banda tira a música da lista", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      html = view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      assert html =~ "Grande é o Senhor saiu do repertório da Banda Jovem."
      refute has_element?(view, "#remove-repertoire-song-#{entry.id}")
      assert Repertoire.list_band_repertoire(band) == []
    end

    test "o Pastor remove do repertório de qualquer banda", %{
      conn: conn,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), repertoire_path(band))

      html = view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      assert html =~ "Grande é o Senhor saiu do repertório da Banda Jovem."
      refute Repertoire.get_band_song(entry.id)
    end

    test "a arquivada sai igual, pelo filtro Arquivada", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, _} = Repertoire.update_band_song(entry, %{"key" => "C", "status" => "archived"})

      {:ok, view, _html} =
        live(log_in_user(conn, leader), repertoire_path(band) <> "?status=archived")

      html = view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      assert html =~ "Grande é o Senhor saiu do repertório da Banda Jovem."
      refute Repertoire.get_band_song(entry.id)
    end

    test "a lista recarrega com o filtro que estava valendo", %{
      conn: conn,
      leader: leader,
      band: band
    } do
      pronta = band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Oceanos"})})
      {:ok, _} = Repertoire.update_band_song(pronta, %{"key" => "C", "status" => "ready"})

      outra_pronta =
        band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Ressuscita-me"})})

      {:ok, _} = Repertoire.update_band_song(outra_pronta, %{"key" => "C", "status" => "ready"})

      {:ok, view, _html} =
        live(log_in_user(conn, leader), repertoire_path(band) <> "?status=ready")

      html = view |> element("#remove-repertoire-song-#{pronta.id}") |> render_click()

      assert html =~ "Ressuscita-me"
      refute html =~ "Grande é o Senhor"
      assert has_element?(view, "#filter-status-ready[aria-pressed='true']")
    end

    # O cancelamento em si é do navegador e não passa pelo `LiveViewTest` — o
    # cenário fica no roteiro manual (US 2.4, cenário 12). O que a suíte alcança
    # é o texto que a confirmação vai mostrar, com a alternativa de arquivar.
    test "o botão pede confirmação e aponta a alternativa de arquivar", %{
      conn: conn,
      leader: leader,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      confirmacao = view |> element("#remove-repertoire-song-#{entry.id}") |> render()

      assert confirmacao =~ "Remover &quot;Grande é o Senhor&quot; do repertório da Banda Jovem?"

      assert confirmacao =~
               "Para só tirar da lista sem perder o registro, marque como arquivada."
    end
  end

  describe "o catálogo depois da remoção" do
    setup %{conn: conn} do
      pastor = pastor_fixture()
      band = band_fixture(%{name: "Banda Jovem"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song})

      %{conn: log_in_user(conn, pastor), band: band, song: song, entry: entry}
    end

    test "a música continua no catálogo, com uma banda a menos na conta", %{
      conn: conn,
      band: band,
      song: song,
      entry: entry
    } do
      band_repertoire_fixture(%{band: band_fixture(%{name: "Banda Kids"}), song: song})

      {:ok, view, _html} = live(conn, repertoire_path(band))
      view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      {:ok, catalogo, html} = live(conn, ~p"/songs")

      assert html =~ "Grande é o Senhor"
      assert catalogo |> element("#song-band-count-#{song.id}") |> render() =~ "1 banda"
    end

    test "removida a última banda que a tocava, a exclusão no catálogo passa", %{
      conn: conn,
      band: band,
      song: song,
      entry: entry
    } do
      {:ok, view, _html} = live(conn, repertoire_path(band))
      view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      {:ok, catalogo, _html} = live(conn, ~p"/songs")
      html = catalogo |> element("#delete-song-#{song.id}") |> render_click()

      assert html =~ "Música Grande é o Senhor excluída."
      refute Repertoire.get_song(song.id)
    end

    test "com a música ainda no repertório de outra banda, a exclusão continua recusada", %{
      conn: conn,
      band: band,
      song: song,
      entry: entry
    } do
      band_repertoire_fixture(%{band: band_fixture(%{name: "Banda Kids"}), song: song})

      {:ok, view, _html} = live(conn, repertoire_path(band))
      view |> element("#remove-repertoire-song-#{entry.id}") |> render_click()

      {:ok, catalogo, _html} = live(conn, ~p"/songs")
      html = catalogo |> element("#delete-song-#{song.id}") |> render_click()

      assert html =~ "Grande é o Senhor está no repertório de Banda Kids."
      assert Repertoire.get_song(song.id)
    end
  end

  describe "quem não pode remover do repertório" do
    setup %{conn: conn} do
      band = band_fixture(%{name: "Banda X"})
      song = song_fixture(%{title: "Grande é o Senhor"})
      entry = band_repertoire_fixture(%{band: band, song: song})

      %{conn: conn, band: band, entry: entry}
    end

    test "o músico comum não vê a ação de remover", %{conn: conn, band: band, entry: entry} do
      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      refute has_element?(view, "#remove-repertoire-song-#{entry.id}")
    end

    test "o músico comum que dispara o evento pelo socket é recusado", %{
      conn: conn,
      band: band,
      entry: entry
    } do
      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), repertoire_path(band))

      html = render_click(view, "remove", %{"id" => to_string(entry.id)})

      assert html =~ "Você não tem permissão para remover músicas do repertório desta banda."
      assert Repertoire.get_band_song(entry.id)
    end

    test "o Líder da Banda Y é recusado no repertório da Banda X", %{
      conn: conn,
      band: banda_x,
      entry: entry
    } do
      leader_y = member_fixture()
      band_fixture(%{leader: leader_y, name: "Banda Y"})

      {:ok, view, _html} = live(log_in_user(conn, leader_y), repertoire_path(banda_x))

      html = render_click(view, "remove", %{"id" => to_string(entry.id)})

      assert html =~ "Você não tem permissão para remover músicas do repertório desta banda."
      assert Repertoire.get_band_song(entry.id)
    end

    test "o vínculo do repertório de outra banda não é removido", %{conn: conn, band: banda_x} do
      de_outra_banda = band_repertoire_fixture()

      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), repertoire_path(banda_x))

      html = render_click(view, "remove", %{"id" => to_string(de_outra_banda.id)})

      assert html =~ "Música não encontrada no repertório desta banda."
      assert Repertoire.get_band_song(de_outra_banda.id)
    end

    test "o vínculo que não existe também não é encontrado", %{conn: conn, band: band} do
      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), repertoire_path(band))

      html = render_click(view, "remove", %{"id" => "0"})

      assert html =~ "Música não encontrada no repertório desta banda."
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
