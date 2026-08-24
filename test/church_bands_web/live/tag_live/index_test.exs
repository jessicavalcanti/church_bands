defmodule ChurchBandsWeb.TagLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Repertoire

  # As sete que a migration cadastra, em ordem alfabética. O banco de teste
  # nasce com elas, e é daí que toda contagem desta tela parte.
  @iniciais ["Adoração", "Celebração", "Louvor", "Natal", "Oferta", "Páscoa", "Santa Ceia"]

  defp tag_chamada(nome), do: Enum.find(Repertoire.list_tags(), &(&1.name == nome))

  describe "autorização de acesso" do
    test "Pastor gerencia as tags", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/admin/tags")
      assert has_element?(view, "#new-tag-button")
    end

    test "Líder de Louvor gerencia as tags", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/admin/tags")
      assert has_element?(view, "#new-tag-button")
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/tags")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    # Liderar uma banda dá poder sobre o elenco dela, não sobre o vocabulário
    # do grupo de louvor inteiro.
    test "Líder de Banda tem o acesso negado", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/tags")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/admin/tags")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end
  end

  describe "a lista de tags" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    # A posição é a do badge de cada tag, e não a do nome solto no HTML:
    # "Louvor" aparece antes de qualquer lista, no papel de acesso de quem está
    # logado no rodapé da barra lateral.
    test "as sete iniciais aparecem em ordem alfabética", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/tags")

      posicoes =
        for nome <- @iniciais do
          tag = tag_chamada(nome)
          assert view |> element("#tag-badge-#{tag.id}") |> render() =~ nome

          :binary.match(html, ~s(id="tag-badge-#{tag.id}"))
        end

      assert posicoes == Enum.sort(posicoes)
    end

    test "cada linha diz em quantas músicas a tag está", %{conn: conn} do
      natal = tag_chamada("Natal")
      oferta = tag_chamada("Oferta")
      pascoa = tag_chamada("Páscoa")

      for _ <- 1..3, do: song_fixture(%{tags: [natal]})
      song_fixture(%{tags: [oferta]})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      assert view |> element("#tag-songs-#{natal.id}") |> render() =~ "3 músicas"
      assert view |> element("#tag-songs-#{oferta.id}") |> render() =~ "1 música"
      assert view |> element("#tag-songs-#{pascoa.id}") |> render() =~ "Nenhuma música"
    end
  end

  describe "cadastro de tag" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "cadastra e volta para a lista com a tag nova", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      view |> element("#new-tag-button") |> render_click()
      assert has_element?(view, "#tag-form")

      view |> form("#tag-form", tag: %{name: "Ministração"}) |> render_submit()

      html = render(view)
      assert html =~ "Tag Ministração cadastrada."
      assert html =~ "Ministração"
      refute has_element?(view, "#tag-form")
    end

    test "recusa nome já cadastrado, sem distinguir maiúsculas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      html = view |> form("#tag-form", tag: %{name: "natal"}) |> render_submit()

      assert html =~ "já existe uma tag com esse nome"
    end

    test "recusa nome já cadastrado, sem distinguir acento", %{conn: conn} do
      tag_fixture(%{name: "Ministração"})

      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      html = view |> form("#tag-form", tag: %{name: "Ministracao"}) |> render_submit()

      assert html =~ "já existe uma tag com esse nome"
    end

    test "recusa nome curto demais", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      html = view |> form("#tag-form", tag: %{name: "N"}) |> render_submit()

      assert html =~ "precisa ter entre 2 e 40 caracteres"
    end

    test "o erro aparece enquanto se digita, antes de enviar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      html = view |> form("#tag-form", tag: %{name: "N"}) |> render_change()

      assert html =~ "precisa ter entre 2 e 40 caracteres"
    end

    test "cancelar fecha o formulário sem cadastrar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      view |> element("#cancel-tag-form") |> render_click()

      refute has_element?(view, "#tag-form")
    end
  end

  describe "renomear tag" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "renomear vale para as músicas que já usavam a tag", %{conn: conn} do
      louvor = tag_chamada("Louvor")
      song = song_fixture(%{title: "Aleluia", tags: [louvor]})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      view |> element("#edit-tag-#{louvor.id}") |> render_click()

      view |> form("#tag-form", tag: %{name: "Louvor congregacional"}) |> render_submit()

      assert render(view) =~ "Tag Louvor congregacional atualizada."

      {:ok, _index, html} = live(conn, ~p"/songs")
      assert html =~ "Louvor congregacional"

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor congregacional"]
    end

    # O índice compara a linha com as outras, e a linha renomeada é ela mesma.
    test "corrigir a grafia da própria tag é permitido", %{conn: conn} do
      tag = tag_fixture(%{name: "Ministracao"})

      {:ok, view, _html} = live(conn, ~p"/admin/tags/#{tag.id}/edit")

      view |> form("#tag-form", tag: %{name: "Ministração"}) |> render_submit()

      assert render(view) =~ "Tag Ministração atualizada."
    end

    test "recusa renomear para o nome de outra tag", %{conn: conn} do
      pascoa = tag_chamada("Páscoa")

      {:ok, view, _html} = live(conn, ~p"/admin/tags/#{pascoa.id}/edit")

      html = view |> form("#tag-form", tag: %{name: "natal"}) |> render_submit()

      assert html =~ "já existe uma tag com esse nome"
    end

    test "tag inexistente devolve para a lista com o recado", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/tags", flash: flash}}} =
               live(conn, ~p"/admin/tags/0/edit")

      assert flash["error"] =~ "Tag não encontrada."

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      refute has_element?(view, "#tag-form")
    end
  end

  describe "exclusão de tag" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "exclui a tag que nenhuma música usa", %{conn: conn} do
      tag = tag_fixture(%{name: "Ministração"})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      view |> element("#delete-tag-#{tag.id}") |> render_click()

      assert render(view) =~ "Tag Ministração excluída."
      refute has_element?(view, "#delete-tag-#{tag.id}")
      assert Repertoire.get_tag(tag.id) == nil
    end

    # A recusa é da lista, não do campo: quem marcou a tag nas músicas não é
    # problema de quem digitou o nome.
    test "recusa excluir tag em uso, dizendo em quantas músicas ela está", %{conn: conn} do
      natal = tag_chamada("Natal")
      for _ <- 1..3, do: song_fixture(%{tags: [natal]})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      view |> element("#delete-tag-#{natal.id}") |> render_click()

      assert render(view) =~
               "A tag Natal está em 3 músicas. " <>
                 "Desmarque a tag nessas músicas antes de excluí-la."

      assert Repertoire.get_tag(natal.id).id == natal.id
    end

    test "a tag em uma música só é recusada no singular", %{conn: conn} do
      natal = tag_chamada("Natal")
      song_fixture(%{tags: [natal]})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      view |> element("#delete-tag-#{natal.id}") |> render_click()

      assert render(view) =~ "A tag Natal está em 1 música."
    end

    test "excluir tag que outra pessoa já excluiu refaz a lista com o recado", %{conn: conn} do
      tag = tag_fixture(%{name: "Ministração"})

      {:ok, view, _html} = live(conn, ~p"/admin/tags")
      {:ok, _tag} = Repertoire.delete_tag(tag)

      view |> element("#delete-tag-#{tag.id}") |> render_click()

      html = render(view)
      assert html =~ "Tag não encontrada."
      refute has_element?(view, "#delete-tag-#{tag.id}")
    end
  end
end
