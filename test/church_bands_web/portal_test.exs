defmodule ChurchBandsWeb.PortalTest do
  @moduledoc """
  A moldura do portal (US 1.9): barra lateral, item destacado, breadcrumb e o
  bloco do usuário no rodapé.

  Esta história não mudou nenhuma regra de negócio, então o que se testa aqui é
  só a moldura. A matriz de permissões continua sendo exercida nos testes de
  cada tela — o único caso de autorização que aparece aqui é o que prova que
  esconder um item do menu não protege nada.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  describe "itens do menu" do
    test "músico comum vê Início, Bandas, Músicas e Pessoas — e não vê Instrumentos nem Convites",
         %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/bands")

      assert has_element?(view, "#home-link[href='/']")
      assert has_element?(view, "#bands-link[href='/bands']")
      assert has_element?(view, "#users-link[href='/users']")
      refute has_element?(view, "#instruments-link")
      refute has_element?(view, "#invites-link")
    end

    # O item saiu da condicional de acesso total na US 2.5, junto com a
    # abertura de `/songs`: esconder a tela de quem ela passou a servir seria
    # esconder o catálogo de quem toca.
    test "músico comum vê Músicas: o catálogo abriu para leitura ampla", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/bands")

      assert has_element?(view, "#songs-link[href='/songs']")
    end

    test "Líder de Banda também vê Músicas", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      {:ok, view, _html} = conn |> log_in_user(leader) |> live(~p"/bands")

      assert has_element?(view, "#songs-link[href='/songs']")
    end

    test "Pastor vê Músicas, Instrumentos e Convites", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/bands")

      assert has_element?(view, "#instruments-link[href='/instruments']")
      assert has_element?(view, "#invites-link[href='/admin/invites']")
      assert has_element?(view, "#songs-link[href='/songs']")
    end

    test "Líder de Louvor vê Músicas, Instrumentos e Convites", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(worship_leader_fixture()) |> live(~p"/bands")

      assert has_element?(view, "#instruments-link[href='/instruments']")
      assert has_element?(view, "#invites-link[href='/admin/invites']")
      assert has_element?(view, "#songs-link[href='/songs']")
    end

    test "o menu segue a ordem Início, Bandas, Músicas, Pessoas, Instrumentos, Convites",
         %{conn: conn} do
      {:ok, _view, html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/bands")

      posicoes =
        Enum.map(
          ~w(home-link bands-link songs-link users-link instruments-link invites-link),
          &:binary.match(html, ~s(id="#{&1}"))
        )

      assert posicoes == Enum.sort(posicoes)
    end

    test "esconder o item não é autorização: forçar a URL continua sendo recusado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/invites")
      assert flash["error"] =~ "não tem permissão"
    end
  end

  describe "item da tela atual" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "a lista de bandas destaca Bandas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bands")

      assert has_element?(view, "#bands-link[data-active='true']")
      refute has_element?(view, "#users-link[data-active='true']")
      refute has_element?(view, "#home-link[data-active='true']")
    end

    test "a tela de dentro de uma banda continua destacando Bandas", %{conn: conn} do
      band = band_fixture()

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}")

      assert has_element?(view, "#bands-link[data-active='true']")
    end

    test "a lista de pessoas destaca Pessoas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#users-link[data-active='true']")
      refute has_element?(view, "#bands-link[data-active='true']")
    end

    test "o catálogo de músicas destaca Músicas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      assert has_element?(view, "#songs-link[data-active='true']")
      refute has_element?(view, "#bands-link[data-active='true']")
    end

    test "o formulário de música continua destacando Músicas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert has_element?(view, "#songs-link[data-active='true']")
    end

    test "Início só fica destacado na própria home, não em toda tela", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      refute has_element?(view, "#home-link[data-active='true']")
    end

    test "o próprio perfil não destaca item nenhum do menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      refute has_element?(view, "#home-link[data-active='true']")
      refute has_element?(view, "#bands-link[data-active='true']")
      refute has_element?(view, "#users-link[data-active='true']")
      refute has_element?(view, "#invites-link[data-active='true']")
    end
  end

  describe "breadcrumb" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, pastor_fixture())}
    end

    test "a home é só Início, sem link", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert trail(html_response(conn, 200)) == ["Início"]
    end

    test "a lista de bandas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bands")

      assert trail(render(view)) == ["Início", "Bandas"]
    end

    test "o cadastro de banda", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bands/new")

      assert trail(render(view)) == ["Início", "Bandas", "Nova banda"]
    end

    test "o detalhe da banda traz o nome dela, não o id", %{conn: conn} do
      band = band_fixture(%{name: "Banda Jovem"})

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}")

      assert trail(render(view)) == ["Início", "Bandas", "Banda Jovem"]
    end

    test "a edição da banda tem o nome como nível anterior, e ele é link", %{conn: conn} do
      band = band_fixture(%{name: "Banda Jovem"})

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}/edit")

      assert trail(render(view)) == ["Início", "Bandas", "Banda Jovem", "Editar"]
      assert has_element?(view, "#breadcrumb a[href='/bands/#{band.id}']", "Banda Jovem")
    end

    test "adicionar integrante", %{conn: conn} do
      band = band_fixture(%{name: "Banda Jovem"})

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}/members/new")

      assert trail(render(view)) == ["Início", "Bandas", "Banda Jovem", "Adicionar integrante"]
    end

    test "o catálogo de músicas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs")

      assert trail(render(view)) == ["Início", "Músicas"]
    end

    test "o cadastro de música", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/songs/new")

      assert trail(render(view)) == ["Início", "Músicas", "Nova música"]
    end

    test "a edição da música traz o título dela, não o id", %{conn: conn} do
      song = song_fixture(%{title: "Grande é o Senhor"})

      {:ok, view, _html} = live(conn, ~p"/songs/#{song.id}/edit")

      assert trail(render(view)) == ["Início", "Músicas", "Grande é o Senhor"]
    end

    test "a lista de pessoas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      assert trail(render(view)) == ["Início", "Pessoas"]
    end

    test "a edição de uma pessoa traz o nome dela", %{conn: conn} do
      user = user_fixture(%{name: "Carla Musicista"})

      {:ok, view, _html} = live(conn, ~p"/users/#{user.id}/edit")

      assert trail(render(view)) == ["Início", "Pessoas", "Carla Musicista"]
    end

    test "o próprio perfil", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      assert trail(render(view)) == ["Início", "Meu perfil"]
    end

    # As tags moram em `/admin`, mas a trilha delas nasce em *Músicas*: é para
    # o catálogo que elas existem, e é de lá que se chega nelas.
    test "as tags, que penduram em Músicas mesmo morando em /admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      assert trail(render(view)) == ["Início", "Músicas", "Tags"]
      assert has_element?(view, "#breadcrumb a[href='/songs']", "Músicas")
    end

    test "o cadastro de tag", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags/new")

      assert trail(render(view)) == ["Início", "Músicas", "Tags", "Nova tag"]
    end

    test "a renomeação da tag traz o nome dela, não o id", %{conn: conn} do
      tag = tag_fixture(%{name: "Ministração"})

      {:ok, view, _html} = live(conn, ~p"/admin/tags/#{tag.id}/edit")

      assert trail(render(view)) == ["Início", "Músicas", "Tags", "Ministração"]
    end

    test "os convites", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      assert trail(render(view)) == ["Início", "Convites"]
    end

    test "o formulário de convite", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites/new")

      assert trail(render(view)) == ["Início", "Convites", "Novo convite"]
    end

    test "todo nível anterior é link e o último é texto", %{conn: conn} do
      band = band_fixture(%{name: "Banda Jovem"})

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}/edit")

      assert has_element?(view, "#breadcrumb a[href='/']", "Início")
      assert has_element?(view, "#breadcrumb a[href='/bands']", "Bandas")
      assert has_element?(view, "#breadcrumb [aria-current='page']", "Editar")
      refute has_element?(view, "#breadcrumb a", "Editar")
    end
  end

  describe "bloco do usuário no rodapé" do
    test "traz nome, papel de acesso, perfil, tema e sair", %{conn: conn} do
      user = user_fixture(%{name: "Ana Souza", global_role: :pastor})

      {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/bands")

      assert html =~ "Ana Souza"
      assert html =~ "Pastor(a)"
      assert has_element?(view, "#profile-link[href='/profile']")
      assert has_element?(view, "#logout-link[href='/logout']")
      assert has_element?(view, "[data-phx-theme='system']")
      assert has_element?(view, "[data-phx-theme='light']")
      assert has_element?(view, "[data-phx-theme='dark']")
    end

    test "sem foto, o bloco mostra as iniciais", %{conn: conn} do
      user = user_fixture(%{name: "Ana Souza"})

      {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/bands")

      assert html =~ "AS"
    end

    test "com foto, o bloco mostra a imagem", %{conn: conn} do
      user = user_fixture(%{name: "Ana Souza"})

      {:ok, user} =
        ChurchBands.Accounts.update_profile(user, %{photo_url: "https://x.test/a.jpg"})

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/bands")

      assert has_element?(
               view,
               "#sidebar-avatar[src='https://x.test/a.jpg'][referrerpolicy='no-referrer']"
             )
    end
  end

  describe "telas públicas" do
    test "o login não tem barra lateral nem breadcrumb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      refute has_element?(view, "#app-sidebar")
      refute has_element?(view, "#breadcrumb")
      refute has_element?(view, "#profile-link")
      refute has_element?(view, "#logout-link")
    end

    test "esqueci minha senha não tem barra lateral", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/password/forgot")

      refute has_element?(view, "#app-sidebar")
      refute has_element?(view, "#breadcrumb")
    end

    test "a ativação de conta não tem barra lateral", %{conn: conn} do
      invite = invite_fixture()

      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      refute has_element?(view, "#app-sidebar")
      refute has_element?(view, "#breadcrumb")
    end

    test "a vitrine de / para visitante mostra Entrar, sem barra lateral", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "home-login-button"
      refute html =~ ~s(id="app-sidebar")
      refute html =~ ~s(id="breadcrumb")
    end

    test "logado, a home é o portal com a saudação e Início destacado", %{conn: conn} do
      user = user_fixture(%{name: "Ana Souza"})

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ "Olá, Ana Souza"
      assert html =~ ~s(id="app-sidebar")
      assert html =~ ~s(data-active="true")
    end
  end

  describe "gaveta do celular" do
    test "a barra lateral sai também como gaveta, com o gatilho que a abre", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(member_fixture()) |> live(~p"/bands")

      assert has_element?(view, "#app-sidebar-mobile")
      assert has_element?(view, "#mobile-sidebar-trigger")
      # A cópia da gaveta usa ids com sufixo, para não duplicar os do desktop.
      assert has_element?(view, "#users-link-mobile[href='/users']")
    end
  end

  describe "barra recolhida sem piscada" do
    # O servidor sempre manda a barra expandida, e o hook do `app.js` só corrige
    # isso depois que a página carrega. Num carregamento inteiro — a home `/` é
    # controller, `/admin/invites` é outra `live_session` — a barra apareceria
    # aberta e fecharia animando. Quem impede é o script inline logo abaixo da
    # barra; por isso o que se testa é que ele existe e que vem **depois** dela.
    test "o portal traz o script que recolhe a barra antes da primeira pintura", %{conn: conn} do
      html = conn |> log_in_user(member_fixture()) |> get(~p"/bands") |> html_response(200)

      assert html =~ ~s(data-sidebar-target="app-sidebar")
      assert html =~ ~s|localStorage.getItem("phx:sidebar")|

      barra = :binary.match(html, ~s(id="app-sidebar")) |> elem(0)
      script = :binary.match(html, ~s|localStorage.getItem("phx:sidebar")|) |> elem(0)
      assert script > barra, "o script precisa vir depois da barra, ou a barra ainda não existe"
    end

    test "a home, que é controller e recarrega a página inteira, também traz o script",
         %{conn: conn} do
      html = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ ~s|localStorage.getItem("phx:sidebar")|
    end

    test "a vitrine do visitante não tem barra, e nem o script", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ ~s|localStorage.getItem("phx:sidebar")|
    end
  end

  describe "a dica do item do menu" do
    # O servidor sempre desenha a barra aberta, e é assim que o portal chega ao
    # navegador. Nesse estado nenhuma dica pode aparecer: o nome do item já está
    # escrito ao lado do ícone. Quem devolve a dica no modo só-ícones é o
    # `group-data-[collapsible=icon]`, sobre o mesmo grupo que a barra usa para
    # saber que está recolhida.
    test "nenhum item do menu mostra a dica enquanto a barra está aberta", %{conn: conn} do
      {:ok, _view, html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/bands")

      dicas = classes_das_dicas(html)

      assert length(dicas) == 6, "são seis itens de menu para o Pastor"

      for classes <- dicas do
        assert "hidden" in classes
        assert "group-data-[collapsible=icon]:block" in classes
      end
    end

    # A gaveta do celular não recolhe: ela abre por cima do conteúdo, com os
    # nomes escritos. É por não estar dentro do grupo da barra fixa que a dica
    # nunca chega a aparecer lá — não é uma segunda regra escrita à mão.
    test "na gaveta do celular não há grupo recolhível em volta da dica", %{conn: conn} do
      {:ok, _view, html} = conn |> log_in_user(pastor_fixture()) |> live(~p"/bands")

      doc = LazyHTML.from_fragment(html)

      assert doc
             |> LazyHTML.query(~s(#app-sidebar-mobile [data-component="tooltip"]))
             |> Enum.any?()

      assert doc |> LazyHTML.query(~s(.group #app-sidebar-mobile)) |> Enum.empty?()
    end
  end

  # Os rótulos do breadcrumb, na ordem. `LazyHTML` devolve o texto de cada
  # item da trilha; o último é o `<span aria-current="page">`, os anteriores
  # são links.
  defp classes_das_dicas(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(#app-sidebar [data-component="tooltip"] [data-part="content"]))
    |> LazyHTML.attribute("class")
    |> Enum.map(&String.split/1)
  end

  defp trail(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#breadcrumb li:not([role='presentation'])")
    |> LazyHTML.text()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
