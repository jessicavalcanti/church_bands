defmodule ChurchBandsWeb.BandLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  describe "leitura ampla" do
    test "qualquer usuário logado vê o elenco de qualquer banda", %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})
      band_member_fixture(%{band: band, user: member_fixture(%{name: "Ana Souza"})})

      conn = log_in_user(conn, member_fixture())

      {:ok, _view, html} = live(conn, ~p"/bands/#{band.id}")

      assert html =~ "Banda Jovem"
      assert html =~ "Carla Líder"
      assert html =~ "Ana Souza"
      assert html =~ "Guitarra"
    end

    test "o líder abre o elenco e é marcado como tal", %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})
      band_member_fixture(%{band: band, user: member_fixture(%{name: "Ana Souza"})})

      conn = log_in_user(conn, member_fixture())

      {:ok, _view, html} = live(conn, ~p"/bands/#{band.id}")

      posicao_lider = :binary.match(html, "Carla Líder") |> elem(0)
      posicao_musico = :binary.match(html, "Ana Souza") |> elem(0)

      assert posicao_lider < posicao_musico
      assert html =~ "Líder"
      assert html =~ "2 no palco"
    end

    test "banda recém-criada mostra o líder sem função", %{conn: conn} do
      band = band_fixture(%{leader: member_fixture(%{name: "Carla Líder"})})

      conn = log_in_user(conn, member_fixture())

      {:ok, _view, html} = live(conn, ~p"/bands/#{band.id}")

      assert html =~ "Carla Líder"
      assert html =~ "Sem função definida"
      assert html =~ "1 no palco"
    end

    test "mostra a descrição da banda quando ela tem uma", %{conn: conn} do
      band = band_fixture(%{description: "Toca na celebração de domingo à noite."})

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}")

      assert view |> element("#band-description") |> render() =~
               "Toca na celebração de domingo à noite."
    end

    test "banda sem descrição não deixa o parágrafo vazio na tela", %{conn: conn} do
      band = band_fixture()

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}")

      refute has_element?(view, "#band-description")
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      band = band_fixture()

      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, ~p"/bands/#{band.id}")

      assert flash["error"] =~ "precisa entrar"
    end

    test "banda inexistente volta para a lista", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} = live(conn, ~p"/bands/0")
      assert flash["error"] =~ "não encontrada"
    end
  end

  describe "ações disponíveis por perfil" do
    test "o Líder da própria banda vê editar, adicionar e remover", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      member = band_member_fixture(%{band: band})

      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/bands/#{band.id}")

      assert has_element?(view, "#edit-band")
      assert has_element?(view, "#add-member")
      assert has_element?(view, "#edit-member-#{member.id}")
      assert has_element?(view, "#remove-member-#{member.id}")
      assert has_element?(view, "#leader-without-role")
    end

    test "Pastor e Líder de Louvor respondem por qualquer banda", %{conn: conn} do
      band = band_fixture()

      for user <- [pastor_fixture(), worship_leader_fixture()] do
        {:ok, view, _html} = live(log_in_user(conn, user), ~p"/bands/#{band.id}")

        assert has_element?(view, "#edit-band")
        assert has_element?(view, "#add-member")
      end
    end

    test "o botão de editar leva ao formulário daquele vínculo", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      member = band_member_fixture(%{band: band})

      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/bands/#{band.id}")

      assert view
             |> element("#edit-member-#{member.id}")
             |> render_click() ==
               {:error,
                {:live_redirect,
                 %{kind: :push, to: "/bands/#{band.id}/members/#{member.id}/edit"}}}
    end

    test "o Líder da Banda X não age na Banda Y", %{conn: conn} do
      leader_x = member_fixture()
      band_fixture(%{leader: leader_x})
      banda_y = band_fixture()

      {:ok, view, _html} = live(log_in_user(conn, leader_x), ~p"/bands/#{banda_y.id}")

      refute has_element?(view, "#edit-band")
      refute has_element?(view, "#add-member")
    end

    test "músico comum só lê", %{conn: conn} do
      band = band_fixture()
      member = band_member_fixture(%{band: band})

      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), ~p"/bands/#{band.id}")

      refute has_element?(view, "#edit-band")
      refute has_element?(view, "#add-member")
      refute has_element?(view, "#edit-member-#{member.id}")
      refute has_element?(view, "#remove-member-#{member.id}")
      refute has_element?(view, "#leader-without-role")
    end
  end

  describe "remover integrante" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      member = band_member_fixture(%{band: band, user: member_fixture(%{name: "Ana Souza"})})

      %{conn: conn, leader: leader, band: band, member: member}
    end

    test "o líder remove um integrante da própria banda", %{
      conn: conn,
      leader: leader,
      band: band,
      member: member
    } do
      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/bands/#{band.id}")

      html = view |> element("#remove-member-#{member.id}") |> render_click()

      assert html =~ "Ana Souza saiu da"
      assert Bands.list_members(band) == []
    end

    test "não remove vínculo de outra banda pelo id", %{
      conn: conn,
      leader: leader,
      band: band
    } do
      de_outra_banda = band_member_fixture()

      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/bands/#{band.id}")

      html = render_click(view, "remove", %{"id" => to_string(de_outra_banda.id)})

      assert html =~ "não encontrado"
      assert Bands.get_member(de_outra_banda.id)
    end

    test "músico comum não remove nem pelo evento", %{conn: conn, band: band, member: member} do
      {:ok, view, _html} = live(log_in_user(conn, member_fixture()), ~p"/bands/#{band.id}")

      html = render_click(view, "remove", %{"id" => to_string(member.id)})

      assert html =~ "não tem permissão"
      assert Bands.get_member(member.id)
    end
  end
end
