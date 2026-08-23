defmodule ChurchBandsWeb.SongLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Repertoire

  describe "listagem do catálogo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "mostra as músicas em ordem alfabética de título", %{conn: conn} do
      song_fixture(%{title: "Ousado Amor"})
      song_fixture(%{title: "Aleluia"})

      {:ok, _view, html} = live(conn, ~p"/songs")

      assert html =~ "Aleluia"
      assert html =~ "Ousado Amor"

      posicoes = [:binary.match(html, "Aleluia"), :binary.match(html, "Ousado Amor")]
      assert posicoes == Enum.sort(posicoes)
    end

    test "mostra artista e BPM de cada música", %{conn: conn} do
      song_fixture(%{title: "Oceanos", artist: "Hillsong United", bpm: 68})

      {:ok, _view, html} = live(conn, ~p"/songs")

      assert html =~ "Hillsong United"
      assert html =~ "68"
    end

    test "a música só com título aparece sem artista, sem BPM e sem ícone de link", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      assert render(view) =~ "Oceanos"
      refute has_element?(view, "#song-reference-#{song.id}")
      refute has_element?(view, "#song-chord-chart-#{song.id}")
    end

    test "os dois ícones-link abrem em nova aba", %{conn: conn} do
      song =
        song_fixture(%{
          title: "Oceanos",
          reference_url: "https://youtube.com/oceanos",
          chord_chart_url: "https://cifraclub.com.br/oceanos"
        })

      {:ok, view, _html} = live(conn, ~p"/songs")

      referencia = view |> element("#song-reference-#{song.id}") |> render()
      assert referencia =~ ~s(href="https://youtube.com/oceanos")
      assert referencia =~ ~s(target="_blank")
      assert referencia =~ ~s(aria-label="Referência de Oceanos")

      cifra = view |> element("#song-chord-chart-#{song.id}") |> render()
      assert cifra =~ ~s(href="https://cifraclub.com.br/oceanos")
      assert cifra =~ ~s(target="_blank")
      assert cifra =~ ~s(aria-label="Cifra de Oceanos")
    end

    test "a música com um link só mostra só aquele ícone", %{conn: conn} do
      song =
        song_fixture(%{title: "Oceanos", chord_chart_url: "https://cifraclub.com.br/oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#song-chord-chart-#{song.id}")
      refute has_element?(view, "#song-reference-#{song.id}")
    end

    test "mostra o estado vazio quando não há música cadastrada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#songs-empty")
      refute has_element?(view, "#songs")
    end

    test "oferece o caminho para cadastrar uma música nova", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#new-song-button[href='/songs/new']")
    end

    test "o botão de editar leva ao formulário da própria música", %{conn: conn} do
      song = song_fixture()

      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#edit-song-#{song.id}[href='/songs/#{song.id}/edit']")
    end
  end

  describe "exclusão de música" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "exclui a música e ela some da lista", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> element("#delete-song-#{song.id}") |> render_click()

      assert html =~ "Música Oceanos excluída."
      refute has_element?(view, "#delete-song-#{song.id}")
      assert Repertoire.list_songs() == []
    end

    test "a exclusão pede confirmação antes", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      assert view |> element("#delete-song-#{song.id}") |> render() =~
               "Excluir a música Oceanos?"
    end

    test "excluir uma música que já saiu do catálogo avisa e recarrega a lista", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})
      outra = song_fixture(%{title: "Aleluia"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      {:ok, _song} = Repertoire.delete_song(song)

      html = render_click(view, "delete", %{"id" => to_string(song.id)})

      assert html =~ "Música não encontrada."
      assert html =~ outra.title
    end
  end

  # A US 2.5 abriu esta tela: até a US 2.1 ela era inteira de acesso total, e
  # músico comum e Líder de Banda eram recusados na porta.
  describe "quem lê o catálogo" do
    test "Pastor lê", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, _view, html} = live(conn, ~p"/songs")
      assert html =~ "Músicas"
    end

    test "músico comum lê o catálogo completo, com artista, BPM, tags e links",
         %{conn: conn} do
      tag = Enum.find(Repertoire.list_tags(), &(&1.name == "Louvor"))

      song =
        song_fixture(%{
          title: "Oceanos",
          artist: "Hillsong United",
          bpm: 68,
          reference_url: "https://youtube.com/oceanos",
          chord_chart_url: "https://cifraclub.com.br/oceanos",
          tags: [tag]
        })

      conn = log_in_user(conn, member_fixture())

      {:ok, view, html} = live(conn, ~p"/songs")

      assert html =~ "Oceanos"
      assert html =~ "Hillsong United"
      assert html =~ "68"
      assert view |> element("#song-tags-#{song.id}") |> render() =~ "Louvor"
      assert has_element?(view, "#song-reference-#{song.id}")
      assert has_element?(view, "#song-chord-chart-#{song.id}")
    end

    # Liderar uma banda não muda o que se vê aqui: o catálogo é do grupo.
    test "Líder de Banda lê o mesmo catálogo", %{conn: conn} do
      song_fixture(%{title: "Oceanos"})

      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, _view, html} = live(log_in_user(conn, leader), ~p"/songs")

      assert html =~ "Oceanos"
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/songs")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "quem escreve no catálogo" do
    test "músico comum não vê botão de escrita nenhum", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), ~p"/songs")

      refute has_element?(view, "#new-song-button")
      refute has_element?(view, "#manage-tags-button")
      refute has_element?(view, "#edit-song-#{song.id}")
      refute has_element?(view, "#delete-song-#{song.id}")
    end

    test "Líder de Louvor vê os quatro botões", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(log_in_user(conn, worship_leader_fixture()), ~p"/songs")

      assert has_element?(view, "#new-song-button")
      assert has_element?(view, "#manage-tags-button")
      assert has_element?(view, "#edit-song-#{song.id}")
      assert has_element?(view, "#delete-song-#{song.id}")
    end

    test "músico comum é recusado ao forçar o cadastro e a edição", %{conn: conn} do
      song = song_fixture()
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/songs/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/songs/#{song.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    # Sem o botão na tela, o evento ainda chega pelo socket: é assim que se
    # prova que a defesa está no servidor, e não em esconder o botão.
    test "músico comum que dispara a exclusão pelo socket é recusado", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), ~p"/songs")

      refute has_element?(view, "#delete-song-#{song.id}")

      render_click(view, "delete", %{"id" => to_string(song.id)})

      assert render(view) =~ "Você não tem permissão para excluir músicas."
      assert Repertoire.get_song(song.id).id == song.id
    end

    test "Líder de Banda recebe a mesma recusa", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/songs")

      render_click(view, "delete", %{"id" => to_string(song.id)})

      assert render(view) =~ "Você não tem permissão para excluir músicas."
      assert Repertoire.get_song(song.id).id == song.id
    end
  end

  describe "tags no catálogo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "as tags da música aparecem como badges abaixo do título", %{conn: conn} do
      tags = Enum.filter(Repertoire.list_tags(), &(&1.name in ["Louvor", "Natal"]))
      song = song_fixture(%{title: "Noite Feliz", tags: tags})

      {:ok, view, _html} = live(conn, ~p"/songs")

      badges = view |> element("#song-tags-#{song.id}") |> render()

      assert badges =~ "Louvor"
      assert badges =~ "Natal"
    end

    test "a música sem tag não mostra badge nenhum — nem um traço", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs")

      assert render(view) =~ "Oceanos"
      refute has_element?(view, "#song-tags-#{song.id}")
    end

    test "o botão Gerenciar tags leva ao cadastro delas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#manage-tags-button[href='/admin/tags']")
    end

    # As marcações vão junto com a música; o vocabulário do grupo não.
    test "excluir a música deixa as tags de pé, com a contagem atualizada", %{conn: conn} do
      natal = Enum.find(Repertoire.list_tags(), &(&1.name == "Natal"))
      song = song_fixture(%{title: "Noite Feliz", tags: [natal]})

      {:ok, view, _html} = live(conn, ~p"/songs")
      view |> element("#delete-song-#{song.id}") |> render_click()

      assert render(view) =~ "Música Noite Feliz excluída."
      assert Enum.find(Repertoire.list_tags(), &(&1.id == natal.id)).song_count == 0
    end
  end

  describe "busca na tela" do
    setup %{conn: conn} do
      song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})
      song_fixture(%{title: "Oceanos", artist: "Hillsong United"})

      %{conn: log_in_user(conn, member_fixture())}
    end

    test "buscar estreita a lista sem sair da tela", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> form("#song-search-form", %{busca: "senhor"}) |> render_change()

      assert html =~ "Grande é o Senhor"
      refute html =~ "Oceanos"
    end

    test "a busca vale para o artista", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> form("#song-search-form", %{busca: "hillsong"}) |> render_change()

      assert html =~ "Oceanos"
      refute html =~ "Grande é o Senhor"
    end

    test "um caractere só não estreita nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> form("#song-search-form", %{busca: "o"}) |> render_change()

      assert html =~ "Grande é o Senhor"
      assert html =~ "Oceanos"
    end

    test "a busca sem resultado oferece limpar, e limpar traz o catálogo de volta",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> form("#song-search-form", %{busca: "zimbabue"}) |> render_change()

      assert html =~ "Nenhuma música encontrada."
      refute html =~ "Nenhuma música cadastrada ainda."

      view |> element("#clear-filters") |> render_click()

      assert render(view) =~ "Oceanos"
      assert_patch(view, ~p"/songs")
    end

    # Catálogo vazio e busca sem resultado são coisas diferentes, e a tela diz
    # qual das duas é.
    test "o catálogo sem música nenhuma tem mensagem própria", %{conn: conn} do
      for song <- Repertoire.list_songs(), do: {:ok, _} = Repertoire.delete_song(song)

      {:ok, _view, html} = live(conn, ~p"/songs")

      assert html =~ "Nenhuma música cadastrada ainda."
      refute html =~ "Nenhuma música encontrada."
    end
  end

  describe "filtro por tag na tela" do
    setup %{conn: conn} do
      natal = Enum.find(Repertoire.list_tags(), &(&1.name == "Natal"))

      song_fixture(%{title: "Noite Feliz", tags: [natal]})
      song_fixture(%{title: "Oceanos"})

      %{conn: log_in_user(conn, member_fixture()), natal: natal}
    end

    test "clicar na tag mostra só as músicas dela e marca o badge",
         %{conn: conn, natal: natal} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      html = view |> element("#filter-tag-#{natal.id}") |> render_click()

      assert html =~ "Noite Feliz"
      refute html =~ "Oceanos"
      assert has_element?(view, "#filter-tag-#{natal.id}[aria-pressed='true']")
    end

    test "clicar de novo na tag selecionada limpa o filtro", %{conn: conn, natal: natal} do
      {:ok, view, _html} = live(conn, ~p"/songs?tag=#{natal.id}")

      assert has_element?(view, "#filter-tag-#{natal.id}[aria-pressed='true']")

      html = view |> element("#filter-tag-#{natal.id}") |> render_click()

      assert html =~ "Oceanos"
      assert has_element?(view, "#filter-tag-#{natal.id}[aria-pressed='false']")
      assert_patch(view, ~p"/songs")
    end

    test "busca e filtro se combinam", %{conn: conn, natal: natal} do
      song_fixture(%{title: "Noite de Paz"})

      {:ok, view, _html} = live(conn, ~p"/songs?tag=#{natal.id}")

      html = view |> form("#song-search-form", %{busca: "noite"}) |> render_change()

      assert html =~ "Noite Feliz"
      refute html =~ "Noite de Paz"
    end

    test "sem tag cadastrada, a barra de tags não aparece", %{conn: conn} do
      for song <- Repertoire.list_songs(), do: {:ok, _} = Repertoire.delete_song(song)
      for tag <- Repertoire.list_tags(), do: {:ok, _} = Repertoire.delete_tag(tag)

      {:ok, view, _html} = live(conn, ~p"/songs")

      refute has_element?(view, "#tag-filter")
    end
  end

  describe "busca e filtro na URL" do
    setup %{conn: conn} do
      natal = Enum.find(Repertoire.list_tags(), &(&1.name == "Natal"))

      song_fixture(%{title: "Noite Feliz", tags: [natal]})
      song_fixture(%{title: "Oceanos"})

      %{conn: log_in_user(conn, member_fixture()), natal: natal}
    end

    # É o que faz o botão voltar do navegador desfazer o filtro em vez de sair
    # da tela, e o resultado de uma busca virar um endereço que se manda para
    # alguém.
    test "buscar e filtrar escrevem na URL", %{conn: conn, natal: natal} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      view |> form("#song-search-form", %{busca: "noite"}) |> render_change()
      assert_patch(view, ~p"/songs?busca=noite")

      view |> element("#filter-tag-#{natal.id}") |> render_click()
      assert_patch(view, ~p"/songs?busca=noite&tag=#{natal.id}")
    end

    test "abrir a URL pronta já traz o campo, o badge e a lista filtrados",
         %{conn: conn, natal: natal} do
      {:ok, view, html} = live(conn, ~p"/songs?busca=noite&tag=#{natal.id}")

      assert html =~ "Noite Feliz"
      refute html =~ "Oceanos"
      assert has_element?(view, "#song-search[value='noite']")
      assert has_element?(view, "#filter-tag-#{natal.id}[aria-pressed='true']")
    end

    # URL torta não vira tela quebrada nem lista vazia inexplicável.
    test "tag que não existe na URL é ignorada", %{conn: conn, natal: natal} do
      {:ok, view, html} = live(conn, ~p"/songs?tag=999999")

      assert html =~ "Noite Feliz"
      assert html =~ "Oceanos"
      assert has_element?(view, "#filter-tag-#{natal.id}[aria-pressed='false']")
    end

    test "tag que nem é número na URL é ignorada", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/songs?tag=abc")

      assert html =~ "Noite Feliz"
      assert html =~ "Oceanos"
    end
  end
end
