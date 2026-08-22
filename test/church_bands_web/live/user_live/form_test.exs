defmodule ChurchBandsWeb.UserLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts

  describe "acesso" do
    test "Pastor abre o formulário de outra pessoa", %{conn: conn} do
      alvo = member_fixture(%{name: "Carla Musicista"})

      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, html} = live(conn, ~p"/users/#{alvo.id}/edit")
      assert has_element?(view, "#user-form")
      assert html =~ "Carla Musicista"
    end

    test "Líder de Louvor abre o formulário de outra pessoa", %{conn: conn} do
      alvo = member_fixture()

      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")
      assert has_element?(view, "#user-form")
    end

    test "músico comum forçando a URL é devolvido à lista", %{conn: conn} do
      alvo = member_fixture()

      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/users", flash: flash}}} =
               live(conn, ~p"/users/#{alvo.id}/edit")

      assert flash["error"] =~ "não tem permissão"
    end

    test "Líder de Banda forçando a URL é devolvido à lista", %{conn: conn} do
      lider = member_fixture()
      band_fixture(%{leader: lider})
      alvo = member_fixture()

      conn = log_in_user(conn, lider)

      assert {:error, {:redirect, %{to: "/users", flash: flash}}} =
               live(conn, ~p"/users/#{alvo.id}/edit")

      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado vai para o login", %{conn: conn} do
      alvo = member_fixture()

      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, ~p"/users/#{alvo.id}/edit")

      assert flash["error"] =~ "precisa entrar"
    end

    test "id inexistente devolve à lista", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:error, {:redirect, %{to: "/users", flash: flash}}} = live(conn, ~p"/users/0/edit")
      assert flash["error"] =~ "não encontrado"
    end

    test "id que não é número devolve à lista sem estourar", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:error, {:redirect, %{to: "/users", flash: flash}}} =
               live(conn, ~p"/users/abacaxi/edit")

      assert flash["error"] =~ "não encontrado"
    end
  end

  describe "edição dos dados" do
    setup %{conn: conn} do
      actor = worship_leader_fixture(%{name: "Bruno Líder de Louvor"})
      alvo = member_fixture(%{name: "Crla Musicista"})

      %{conn: log_in_user(conn, actor), actor: actor, alvo: alvo}
    end

    test "corrige o nome e volta para a lista", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      assert {:ok, _index, html} =
               view
               |> form("#user-form", user: %{name: "Carla Musicista"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      assert html =~ "Dados de Carla Musicista atualizados."
      assert html =~ "Carla Musicista"
      assert Accounts.get_user(alvo.id).name == "Carla Musicista"
    end

    test "corrige telefone e foto", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      view
      |> form("#user-form", user: %{phone: "(11) 98888-7777", photo_url: "https://e.com/c.jpg"})
      |> render_submit()

      alvo = Accounts.get_user(alvo.id)
      assert alvo.phone == "(11) 98888-7777"
      assert alvo.photo_url == "https://e.com/c.jpg"
    end

    test "promove alguém a Líder de Louvor", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      view |> form("#user-form", user: %{global_role: "worship_leader"}) |> render_submit()

      assert Accounts.get_user(alvo.id).global_role == :worship_leader
    end

    test "mostra o erro sem salvar quando o dado não presta", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      html = view |> form("#user-form", user: %{name: ""}) |> render_submit()

      assert html =~ "não pode ficar em branco"
      assert has_element?(view, "#user-form")
      assert Accounts.get_user(alvo.id).name == "Crla Musicista"
    end

    test "mostra a foto de quem tem uma", %{conn: conn} do
      alvo =
        member_fixture(%{name: "Elis Fotografada", photo_url: "https://exemplo.com/elis.jpg"})

      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      assert has_element?(view, "#user-form-photo[src='https://exemplo.com/elis.jpg']")
      refute has_element?(view, "#user-form-photo-placeholder")
    end

    test "mostra um lugar para a foto de quem não tem", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      assert has_element?(view, "#user-form-photo-placeholder")
      refute has_element?(view, "#user-form-photo")
    end

    test "o e-mail aparece para conferência, fora do formulário", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      assert view |> element("#user-form-email") |> render() =~ alvo.email
      refute has_element?(view, "#user-form input[name='user[email]']")
    end

    test "não existe campo de senha nesta tela", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      refute has_element?(view, "#user-form input[type='password']")
    end

    test "forjar o e-mail no formulário não troca a credencial", %{conn: conn, alvo: alvo} do
      {:ok, view, _html} = live(conn, ~p"/users/#{alvo.id}/edit")

      view
      |> form("#user-form", user: %{name: "Carla Musicista"})
      |> render_submit(%{"user" => %{"email" => "invasora@exemplo.com"}})

      assert Accounts.get_user(alvo.id).email == alvo.email
    end
  end

  describe "travas do papel de acesso" do
    test "recusa mudar o próprio papel e explica por quê", %{conn: conn} do
      # Outra pessoa com acesso total existe, então a recusa é por ser o
      # próprio papel — não por deixar o sistema sem ninguém.
      worship_leader_fixture()
      actor = pastor_fixture(%{name: "Ana Pastora"})

      conn = log_in_user(conn, actor)
      {:ok, view, _html} = live(conn, ~p"/users/#{actor.id}/edit")

      html = view |> form("#user-form", user: %{global_role: "member"}) |> render_submit()

      assert html =~ "outra pessoa com acesso total precisa fazer isso"
      assert Accounts.get_user(actor.id).global_role == :pastor
    end

    test "avisa na tela antes de tentar, quando é o próprio cadastro", %{conn: conn} do
      worship_leader_fixture()
      actor = pastor_fixture()

      conn = log_in_user(conn, actor)
      {:ok, view, _html} = live(conn, ~p"/users/#{actor.id}/edit")

      assert view |> element("#role-hint") |> render() =~
               "Você não muda o seu próprio papel de acesso"
    end

    test "recusa rebaixar quem é o único com acesso total", %{conn: conn} do
      unico = worship_leader_fixture()

      conn = log_in_user(conn, unico)
      {:ok, view, _html} = live(conn, ~p"/users/#{unico.id}/edit")

      html = view |> form("#user-form", user: %{global_role: "member"}) |> render_submit()

      assert html =~ "o sistema ficaria sem ninguém com acesso total"
      assert Accounts.get_user(unico.id).global_role == :worship_leader
    end

    test "a recusa aparece já na validação, antes de salvar", %{conn: conn} do
      worship_leader_fixture()
      actor = pastor_fixture()

      conn = log_in_user(conn, actor)
      {:ok, view, _html} = live(conn, ~p"/users/#{actor.id}/edit")

      html = view |> form("#user-form", user: %{global_role: "member"}) |> render_change()

      assert html =~ "outra pessoa com acesso total precisa fazer isso"
    end

    test "quem tem acesso total corrige os próprios nome e contato por aqui", %{conn: conn} do
      actor = pastor_fixture(%{name: "Ana Pastra"})

      conn = log_in_user(conn, actor)
      {:ok, view, _html} = live(conn, ~p"/users/#{actor.id}/edit")

      view |> form("#user-form", user: %{name: "Ana Pastora"}) |> render_submit()

      assert Accounts.get_user(actor.id).name == "Ana Pastora"
    end
  end
end
