defmodule ChurchBandsWeb.BandLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  describe "listagem" do
    test "qualquer usuário logado vê as bandas cadastradas", %{conn: conn} do
      leader = member_fixture(%{name: "Líder Fulano"})
      band_fixture(%{leader: leader, name: "Banda Jovem"})

      conn = log_in_user(conn, member_fixture())

      {:ok, _view, html} = live(conn, ~p"/bands")
      assert html =~ "Banda Jovem"
      assert html =~ "Líder Fulano"
    end

    test "mostra o estado vazio quando não há bandas", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/bands")
      assert has_element?(view, "#bands-empty")
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/bands")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "ações disponíveis por perfil" do
    test "Líder de Louvor vê os botões de cadastrar, editar e excluir", %{conn: conn} do
      band = band_fixture()
      conn = log_in_user(conn, worship_leader_fixture())

      {:ok, view, _html} = live(conn, ~p"/bands")

      assert has_element?(view, "#new-band-button")
      assert has_element?(view, "#edit-band-#{band.id}")
      assert has_element?(view, "#delete-band-#{band.id}")
    end

    test "Líder de Banda só vê o botão de editar a própria banda", %{conn: conn} do
      leader = member_fixture()
      propria = band_fixture(%{leader: leader})
      alheia = band_fixture()

      conn = log_in_user(conn, leader)

      {:ok, view, _html} = live(conn, ~p"/bands")

      refute has_element?(view, "#new-band-button")
      assert has_element?(view, "#edit-band-#{propria.id}")
      refute has_element?(view, "#edit-band-#{alheia.id}")
      refute has_element?(view, "#delete-band-#{propria.id}")
    end

    test "músico comum não vê nenhum botão de escrita", %{conn: conn} do
      band = band_fixture()
      conn = log_in_user(conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/bands")

      refute has_element?(view, "#new-band-button")
      refute has_element?(view, "#edit-band-#{band.id}")
      refute has_element?(view, "#delete-band-#{band.id}")
    end
  end

  describe "exclusão de banda" do
    test "Líder de Louvor exclui uma banda", %{conn: conn} do
      band = band_fixture(%{name: "Banda Encerrada"})
      conn = log_in_user(conn, worship_leader_fixture())

      {:ok, view, _html} = live(conn, ~p"/bands")

      html = view |> element("#delete-band-#{band.id}") |> render_click()

      assert html =~ "Banda Encerrada excluída."
      assert Bands.get_band(band.id) == nil
    end

    test "Líder de Banda não consegue excluir a própria banda nem pelo evento", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      conn = log_in_user(conn, leader)
      {:ok, view, _html} = live(conn, ~p"/bands")

      html = render_click(view, "delete", %{"id" => to_string(band.id)})

      assert html =~ "não tem permissão para excluir"
      assert Bands.get_band(band.id)
    end

    test "músico comum não consegue excluir nem pelo evento", %{conn: conn} do
      band = band_fixture()

      conn = log_in_user(conn, member_fixture())
      {:ok, view, _html} = live(conn, ~p"/bands")

      html = render_click(view, "delete", %{"id" => to_string(band.id)})

      assert html =~ "não tem permissão para excluir"
      assert Bands.get_band(band.id)
    end
  end
end
