defmodule ChurchBandsWeb.UserLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  describe "listagem" do
    test "músico comum vê todo mundo com nome, e-mail, telefone e papel", %{conn: conn} do
      member_fixture(%{
        name: "Carla Musicista",
        email: "carla@exemplo.com",
        phone: "(11) 98888-7777"
      })

      pastor_fixture(%{name: "Ana Pastora"})

      conn = log_in_user(conn, member_fixture())
      {:ok, _view, html} = live(conn, ~p"/users")

      assert html =~ "Carla Musicista"
      assert html =~ "carla@exemplo.com"
      assert html =~ "(11) 98888-7777"
      assert html =~ "Ana Pastora"
      assert html =~ "Pastor(a)"
    end

    test "mostra as bandas em que cada pessoa toca", %{conn: conn} do
      lider = member_fixture(%{name: "Carla Musicista"})
      band_fixture(%{leader: lider, name: "Banda Jovem"})

      vocalista = member_fixture(%{name: "Bruno Vocalista"})

      band_member_fixture(%{
        band: band_fixture(%{name: "Banda do Culto"}),
        user: vocalista,
        type: :vocalist,
        voice_part: "Tenor"
      })

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      bandas_da_carla = view |> element("#user-bands-#{lider.id}") |> render()
      assert bandas_da_carla =~ "Banda Jovem"
      assert bandas_da_carla =~ "Líder"

      bandas_do_bruno = view |> element("#user-bands-#{vocalista.id}") |> render()
      assert bandas_do_bruno =~ "Banda do Culto"
      assert bandas_do_bruno =~ "Vocal — Tenor"
    end

    test "quem não toca em banda nenhuma aparece assim mesmo", %{conn: conn} do
      pastora = pastor_fixture(%{name: "Ana Pastora"})

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#user-bands-empty-#{pastora.id}")
    end

    test "mostra a foto de quem tem e um lugar para ela em quem não tem", %{conn: conn} do
      com_foto = member_fixture(%{photo_url: "https://exemplo.com/carla.jpg"})
      sem_foto = member_fixture()

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(
               view,
               "#user-photo-#{com_foto.id}[src='https://exemplo.com/carla.jpg']"
             )

      assert has_element?(view, "#user-photo-placeholder-#{sem_foto.id}")
    end

    test "convite ainda não aceito não aparece na lista", %{conn: conn} do
      invite = invite_fixture()

      conn = log_in_user(conn, member_fixture())
      {:ok, _view, html} = live(conn, ~p"/users")

      refute html =~ invite.email
    end

    test "quem ainda não ativou a conta não aparece na lista", %{conn: conn} do
      user_fixture(%{name: "Pendente da Silva", confirmed_at: nil})

      conn = log_in_user(conn, member_fixture())
      {:ok, _view, html} = live(conn, ~p"/users")

      refute html =~ "Pendente da Silva"
    end

    test "a barra do topo leva à lista de pessoas", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/bands")

      assert has_element?(view, "#users-link[href='/users']")
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/users")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "busca" do
    setup %{conn: conn} do
      member_fixture(%{name: "Carla Musicista", email: "carla@exemplo.com"})
      member_fixture(%{name: "Bruno Vocalista", email: "bruno@exemplo.com"})

      %{conn: log_in_user(conn, member_fixture(%{name: "Quem Olha"}))}
    end

    test "estreita a lista por nome", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      html = view |> form("#user-search-form", search: "carla") |> render_change()

      assert html =~ "Carla Musicista"
      refute html =~ "Bruno Vocalista"
    end

    test "estreita a lista por e-mail", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      html = view |> form("#user-search-form", search: "bruno@") |> render_change()

      assert html =~ "Bruno Vocalista"
      refute html =~ "Carla Musicista"
    end

    test "busca sem resultado mostra o aviso", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      view |> form("#user-search-form", search: "ninguém com esse nome") |> render_change()

      assert has_element?(view, "#users-empty")
    end

    test "limpar a busca traz todo mundo de volta", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      view |> form("#user-search-form", search: "carla") |> render_change()
      html = view |> form("#user-search-form", search: "") |> render_change()

      assert html =~ "Carla Musicista"
      assert html =~ "Bruno Vocalista"
    end
  end

  describe "botão de editar" do
    test "Pastor vê o botão de editar de cada pessoa", %{conn: conn} do
      alvo = member_fixture()

      conn = log_in_user(conn, pastor_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#edit-user-#{alvo.id}")
    end

    test "Líder de Louvor vê o botão de editar", %{conn: conn} do
      alvo = member_fixture()

      conn = log_in_user(conn, worship_leader_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#edit-user-#{alvo.id}")
    end

    test "músico comum não vê botão de editar nenhum", %{conn: conn} do
      alvo = member_fixture()

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      refute has_element?(view, "#edit-user-#{alvo.id}")
    end

    test "Líder de Banda não vê botão de editar", %{conn: conn} do
      lider = member_fixture()
      band_fixture(%{leader: lider})
      alvo = member_fixture()

      conn = log_in_user(conn, lider)
      {:ok, view, _html} = live(conn, ~p"/users")

      refute has_element?(view, "#edit-user-#{alvo.id}")
    end

    test "o botão leva ao formulário daquela pessoa", %{conn: conn} do
      alvo = member_fixture(%{name: "Carla Musicista"})

      conn = log_in_user(conn, pastor_fixture())
      {:ok, view, _html} = live(conn, ~p"/users")

      assert {:ok, _form, html} =
               view
               |> element("#edit-user-#{alvo.id}")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/#{alvo.id}/edit")

      assert html =~ "Editar Carla Musicista"
    end
  end
end
