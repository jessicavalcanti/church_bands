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

  describe "quem acessa o catálogo" do
    test "Pastor acessa", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, _view, html} = live(conn, ~p"/songs")
      assert html =~ "Músicas"
    end

    test "Líder de Banda tem o acesso negado", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/songs")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/songs")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/songs")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
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
end
