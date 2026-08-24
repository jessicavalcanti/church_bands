defmodule ChurchBandsWeb.SongLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Repertoire

  describe "cadastro de música" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "cadastra a música com todos os campos preenchidos", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert {:ok, _view, html} =
               view
               |> form("#song-form",
                 song: %{
                   title: "Grande é o Senhor",
                   artist: "Adhemar de Campos",
                   bpm: "72",
                   reference_url: "https://youtube.com/watch?v=abc",
                   chord_chart_url: "https://cifraclub.com.br/grande-e-o-senhor"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/songs")

      assert html =~ "Música Grande é o Senhor cadastrada."
      assert html =~ "Grande é o Senhor"
      assert html =~ "Adhemar de Campos"

      assert [song] = Repertoire.list_songs()
      assert song.bpm == 72
    end

    test "cadastra a música informando só o título", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert {:ok, _view, html} =
               view
               |> form("#song-form", song: %{title: "Oceanos"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/songs")

      assert html =~ "Música Oceanos cadastrada."

      assert [song] = Repertoire.list_songs()
      assert song.artist == nil
      assert song.bpm == nil
    end

    test "recusa o cadastro sem título e aponta o campo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      html = view |> form("#song-form", song: %{title: ""}) |> render_submit()

      assert html =~ "informe o título da música"
      assert Repertoire.list_songs() == []
    end

    test "recusa o link de cifra que não começa com http", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      html =
        view
        |> form("#song-form",
          song: %{title: "Oceanos", chord_chart_url: "cifraclub.com.br/oceanos"}
        )
        |> render_submit()

      assert html =~ "precisa começar com http:// ou https://"
      assert Repertoire.list_songs() == []
    end

    test "grava o título sem os espaços das pontas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view
      |> form("#song-form", song: %{title: "  Oceanos  "})
      |> render_submit()

      assert [song] = Repertoire.list_songs()
      assert song.title == "Oceanos"
    end

    test "aponta o campo obrigatório enquanto a pessoa digita", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      html = view |> form("#song-form", song: %{title: ""}) |> render_change()

      assert html =~ "informe o título da música"
    end

    test "cancelar devolve à lista sem cadastrar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert has_element?(view, "#cancel-song-form[href='/songs']")
      assert Repertoire.list_songs() == []
    end
  end

  describe "aviso de músicas parecidas" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "mostra a música já cadastrada com título parecido, com artista e link", %{conn: conn} do
      existente = song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      html = view |> form("#song-form", song: %{title: "Grande e o Senhôr"}) |> render_change()

      assert html =~ "Músicas parecidas já cadastradas"
      assert html =~ "Confira se não é a mesma. Você pode salvar mesmo assim."
      assert html =~ "Grande é o Senhor"
      assert html =~ "Adhemar de Campos"

      link = view |> element("#similar-song-#{existente.id}") |> render()
      assert link =~ ~s(href="/songs/#{existente.id}/edit")
      assert link =~ ~s(target="_blank")
    end

    test "não consulta parecidas com menos de três caracteres", %{conn: conn} do
      song_fixture(%{title: "Grande é o Senhor"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> form("#song-form", song: %{title: "Gr"}) |> render_change()

      refute has_element?(view, "#similar-songs")
    end

    test "não mostra o bloco quando nada é parecido", %{conn: conn} do
      song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> form("#song-form", song: %{title: "Aleluia"}) |> render_change()

      refute has_element?(view, "#similar-songs")
    end

    test "lista no máximo cinco parecidas", %{conn: conn} do
      for i <- 1..8, do: song_fixture(%{title: "Aleluia #{i}"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> form("#song-form", song: %{title: "Aleluia"}) |> render_change()

      assert view |> element("#similar-songs") |> render() |> parecidas_listadas() == 5
    end

    test "salvar com o aviso na tela cadastra a segunda música mesmo assim", %{conn: conn} do
      song_fixture(%{title: "Grande é o Senhor"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> form("#song-form", song: %{title: "Grande e o Senhor"}) |> render_change()

      assert {:ok, _view, _html} =
               view
               |> form("#song-form", song: %{title: "Grande e o Senhor"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/songs")

      assert length(Repertoire.list_songs()) == 2
    end

    test "ao editar, a própria música não aparece no aviso e a outra sim", %{conn: conn} do
      song = song_fixture(%{title: "Grande é o Senhor"})
      outra = song_fixture(%{title: "Grande e o Senhor"})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      assert has_element?(view, "#similar-song-#{outra.id}")
      refute has_element?(view, "#similar-song-#{song.id}")
    end
  end

  describe "edição de música" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "corrige o artista e a lista mostra o dado atualizado", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos", artist: "Errado"})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      assert {:ok, _view, html} =
               view
               |> form("#song-form", song: %{artist: "Hillsong United"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/songs")

      assert html =~ "Música Oceanos atualizada."
      assert html =~ "Hillsong United"
      refute html =~ "Errado"
    end

    test "o formulário abre com os dados que já estão gravados", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos", artist: "Hillsong United", bpm: 68})

      {:ok, _view, html} = live(conn, ~p"/songs/#{song.id}/edit")

      assert html =~ "Oceanos"
      assert html =~ "Hillsong United"
      assert html =~ "68"
    end

    test "recusa a edição que apaga o título", %{conn: conn} do
      song = song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      html = view |> form("#song-form", song: %{title: ""}) |> render_submit()

      assert html =~ "informe o título da música"
      assert Repertoire.get_song(song.id).title == "Oceanos"
    end

    test "editar um id que não existe devolve à lista com o aviso", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/songs", flash: flash}}} =
               live(conn, ~p"/songs/999999/edit")

      assert flash["error"] =~ "Música não encontrada."
    end

    test "editar um id que nem é número devolve à lista com o aviso", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/songs", flash: flash}}} =
               live(conn, ~p"/songs/inventado/edit")

      assert flash["error"] =~ "Música não encontrada."
    end
  end

  describe "quem acessa o formulário" do
    test "Pastor acessa o cadastro", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/songs/new")
      assert has_element?(view, "#song-form")
    end

    test "Líder de Banda tem o acesso negado ao cadastro", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/songs/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "Líder de Banda tem o acesso negado à edição", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      song = song_fixture()

      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/songs/#{song.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "músico comum tem o acesso negado ao cadastro", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/songs/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "músico comum tem o acesso negado à edição", %{conn: conn} do
      song = song_fixture()
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/songs/#{song.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/songs/new")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "tags da música" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    defp tag_chamada(nome), do: Enum.find(Repertoire.list_tags(), &(&1.name == nome))

    test "as tags cadastradas aparecem como badges alternáveis", %{conn: conn} do
      tag = tag_fixture(%{name: "Ministração"})

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert view |> element("#toggle-tag-#{tag.id}") |> render() =~ "Ministração"
      assert has_element?(view, "#toggle-tag-#{tag.id}[aria-pressed='false']")
    end

    test "cadastra a música com as tags marcadas", %{conn: conn} do
      louvor = tag_chamada("Louvor")
      natal = tag_chamada("Natal")

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> element("#toggle-tag-#{louvor.id}") |> render_click()
      view |> element("#toggle-tag-#{natal.id}") |> render_click()

      assert has_element?(view, "#toggle-tag-#{louvor.id}[aria-pressed='true']")

      view |> form("#song-form", song: %{title: "Noite Feliz"}) |> render_submit()

      assert [song] = Enum.filter(Repertoire.list_songs(), &(&1.title == "Noite Feliz"))
      assert Enum.map(song.tags, & &1.name) == ["Louvor", "Natal"]
    end

    test "cadastra a música sem marcar tag nenhuma", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> form("#song-form", song: %{title: "Oceanos"}) |> render_submit()

      assert [song] = Enum.filter(Repertoire.list_songs(), &(&1.title == "Oceanos"))
      assert song.tags == []
    end

    test "a música em edição abre com as tags dela já marcadas", %{conn: conn} do
      louvor = tag_chamada("Louvor")
      natal = tag_chamada("Natal")
      song = song_fixture(%{tags: [louvor, natal]})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      assert has_element?(view, "#toggle-tag-#{louvor.id}[aria-pressed='true']")
      assert has_element?(view, "#toggle-tag-#{natal.id}[aria-pressed='true']")
      assert has_element?(view, "#toggle-tag-#{tag_chamada("Oferta").id}[aria-pressed='false']")
    end

    test "desmarcar uma tag na edição deixa a música só com a outra", %{conn: conn} do
      louvor = tag_chamada("Louvor")
      natal = tag_chamada("Natal")
      song = song_fixture(%{tags: [louvor, natal]})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      view |> element("#toggle-tag-#{natal.id}") |> render_click()
      view |> form("#song-form", song: %{title: song.title}) |> render_submit()

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor"]
    end

    # As marcadas moram no socket, e não no changeset: quem clicou nos badges
    # não perde a escolha porque esqueceu o título.
    test "a validação que falha não desmarca as tags já escolhidas", %{conn: conn} do
      louvor = tag_chamada("Louvor")

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> element("#toggle-tag-#{louvor.id}") |> render_click()

      html = view |> form("#song-form", song: %{title: ""}) |> render_submit()

      assert html =~ "informe o título da música"
      assert has_element?(view, "#toggle-tag-#{louvor.id}[aria-pressed='true']")
    end

    test "clicar de novo no mesmo badge desmarca a tag", %{conn: conn} do
      louvor = tag_chamada("Louvor")

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      view |> element("#toggle-tag-#{louvor.id}") |> render_click()
      view |> element("#toggle-tag-#{louvor.id}") |> render_click()

      assert has_element?(view, "#toggle-tag-#{louvor.id}[aria-pressed='false']")

      view |> form("#song-form", song: %{title: "Aleluia"}) |> render_submit()

      assert [song] = Enum.filter(Repertoire.list_songs(), &(&1.title == "Aleluia"))
      assert song.tags == []
    end

    # A lista carregada do banco é quem diz o que é uma tag de verdade: id que
    # veio da tela e não está nela não vira marcação.
    test "id de tag que não existe é ignorado", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      render_click(view, "toggle_tag", %{"id" => "0"})

      view |> form("#song-form", song: %{title: "Aleluia"}) |> render_submit()

      assert [song] = Enum.filter(Repertoire.list_songs(), &(&1.title == "Aleluia"))
      assert song.tags == []
    end

    test "sem tag nenhuma cadastrada, o bloco mostra só o link de gerenciar", %{conn: conn} do
      for tag <- Repertoire.list_tags(), do: {:ok, _} = Repertoire.delete_tag(tag)

      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert has_element?(view, "#no-tags-yet")
      refute has_element?(view, "#song-tags")
      assert has_element?(view, "#manage-tags-link[href='/admin/tags']")
    end

    test "o link de gerenciar tags leva ao cadastro delas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert has_element?(view, "#manage-tags-link[href='/admin/tags']")
    end
  end

  # Quantos itens o bloco de parecidas listou.
  defp parecidas_listadas(html) do
    html |> String.split("<li") |> length() |> Kernel.-(1)
  end
end
