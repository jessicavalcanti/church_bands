defmodule ChurchBandsWeb.ProfileLiveTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts

  describe "acesso à tela de perfil" do
    test "músico comum acessa o próprio perfil", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/profile")
      assert has_element?(view, "#profile-form")
    end

    test "Líder de Louvor acessa o próprio perfil", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/profile")
      assert has_element?(view, "#profile-form")
    end

    test "Pastor acessa o próprio perfil", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/profile")
      assert has_element?(view, "#profile-form")
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/profile")
      assert flash["error"] =~ "precisa entrar"
    end

    test "a barra do topo leva ao perfil", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/bands")

      assert has_element?(view, "#profile-link[href='/profile']")
    end

    test "visitante não vê o atalho do perfil na barra do topo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      refute has_element?(view, "#profile-link")
    end
  end

  describe "edição dos próprios dados" do
    setup %{conn: conn} do
      user = member_fixture(%{name: "Carla Musicista"})
      %{conn: log_in_user(conn, user), user: user}
    end

    test "altera o telefone e salva", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      html =
        view
        |> form("#profile-form", user: %{phone: "(11) 98888-7777"})
        |> render_submit()

      assert html =~ "Perfil atualizado."
      assert Accounts.get_user(user.id).phone == "(11) 98888-7777"
    end

    test "altera a foto e mostra a imagem na tela", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      refute has_element?(view, "#profile-photo")
      assert has_element?(view, "#profile-photo-placeholder")

      view
      |> form("#profile-form", user: %{photo_url: "https://exemplo.com/carla.jpg"})
      |> render_submit()

      assert has_element?(
               view,
               "#profile-photo[src='https://exemplo.com/carla.jpg'][referrerpolicy='no-referrer']"
             )

      assert Accounts.get_user(user.id).photo_url == "https://exemplo.com/carla.jpg"
    end

    test "apaga o telefone quando o campo fica em branco", %{conn: conn} do
      user = member_fixture(%{phone: "11988887777"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/profile")

      view |> form("#profile-form", user: %{phone: ""}) |> render_submit()

      assert is_nil(Accounts.get_user(user.id).phone)
    end

    test "mostra erro quando o telefone tem letras", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      html =
        view
        |> form("#profile-form", user: %{phone: "me liga aí"})
        |> render_submit()

      assert html =~ "pode ter apenas números"
      assert is_nil(Accounts.get_user(user.id).phone)
    end

    test "mostra erro quando a foto não é um endereço http", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      html =
        view
        |> form("#profile-form", user: %{photo_url: "carla.jpg"})
        |> render_submit()

      assert html =~ "começando com http:// ou https://"
      assert is_nil(Accounts.get_user(user.id).photo_url)
    end

    test "valida enquanto digita, sem salvar", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile")

      html =
        view
        |> form("#profile-form", user: %{phone: "123"})
        |> render_change()

      assert html =~ "precisa ter ao menos 8 números"
      assert is_nil(Accounts.get_user(user.id).phone)
    end
  end

  describe "dados estruturais são somente leitura" do
    test "e-mail e papel aparecem sem campo de formulário", %{conn: conn} do
      user = worship_leader_fixture(%{name: "Bruno Líder de Louvor"})
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/profile")

      assert html =~ "Bruno Líder de Louvor"
      assert html =~ "Líder de Louvor"
      assert has_element?(view, "#structural-fields")

      refute has_element?(view, "#profile-form input[name='user[email]']")
      refute has_element?(view, "#profile-form select[name='user[global_role]']")
    end

    test "o nome, esse sim, tem campo de formulário", %{conn: conn} do
      # Nome não é dado estrutural: quem o digitou foi a própria pessoa, na
      # ativação da conta, e um erro ali precisa ter conserto pela mão dela.
      user = member_fixture(%{name: "Crla Musicista"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/profile")

      assert has_element?(view, "#profile-form input[name='user[name]']")

      html = view |> form("#profile-form", user: %{name: "Carla Musicista"}) |> render_submit()

      assert html =~ "Perfil atualizado."
      assert Accounts.get_user(user.id).name == "Carla Musicista"
    end

    test "nome em branco é recusado e nada é gravado", %{conn: conn} do
      user = member_fixture(%{name: "Carla Musicista"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/profile")

      html = view |> form("#profile-form", user: %{name: ""}) |> render_submit()

      assert html =~ "não pode ficar em branco"
      assert Accounts.get_user(user.id).name == "Carla Musicista"
    end

    test "músico que força o papel de acesso no formulário continua músico", %{conn: conn} do
      user = member_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/profile")

      # O formulário não tem esse campo: o parâmetro só chega aqui se for
      # forjado no navegador. `profile_changeset/2` não o aceita.
      view
      |> render_submit("save", %{
        "user" => %{"phone" => "11988887777", "global_role" => "pastor"}
      })

      updated = Accounts.get_user(user.id)
      assert updated.global_role == :member
      assert updated.phone == "11988887777"
    end

    test "músico que força a função na banda no formulário não a altera", %{conn: conn} do
      user = member_fixture()
      band = band_fixture(%{name: "Banda Jovem"})

      member =
        band_member_fixture(%{
          band: band,
          user: user,
          type: :vocalist,
          voice_part: "Tenor"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/profile")

      view
      |> render_submit("save", %{
        "user" => %{
          "phone" => "11988887777",
          "band_members" => %{"0" => %{"id" => member.id, "instrument" => "Guitarra"}}
        }
      })

      reloaded = ChurchBands.Bands.get_member(member.id)
      assert reloaded.type == :vocalist
      assert reloaded.voice_part == "Tenor"
      assert is_nil(reloaded.instrument)
    end
  end

  describe "minhas bandas" do
    test "lista as bandas do músico com a função em cada uma", %{conn: conn} do
      user = member_fixture()
      jovem = band_fixture(%{name: "Banda Jovem"})
      domingo = band_fixture(%{name: "Banda Domingo"})

      band_member_fixture(%{band: jovem, user: user, type: :instrumentalist, instrument: "Baixo"})
      band_member_fixture(%{band: domingo, user: user, type: :vocalist, voice_part: "Tenor"})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/profile")

      assert html =~ "Banda Jovem"
      assert html =~ "Baixo"
      assert html =~ "Banda Domingo"
      assert html =~ "Vocal — Tenor"
    end

    test "marca a banda que o usuário lidera e cobra a função que falta", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader, name: "Banda Jovem"})

      conn = log_in_user(conn, leader)
      {:ok, _view, html} = live(conn, ~p"/profile")

      assert html =~ "Banda Jovem"
      assert html =~ "Líder"
      assert html =~ "Sem função definida"
    end

    test "avisa quem ainda não toca em banda nenhuma", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/profile")

      assert has_element?(view, "#my-bands-empty")
    end
  end
end
