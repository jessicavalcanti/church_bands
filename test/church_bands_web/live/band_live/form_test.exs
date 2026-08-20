defmodule ChurchBandsWeb.BandLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  describe "autorização para cadastrar banda" do
    test "Líder de Louvor acessa o formulário", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/bands/new")
      assert has_element?(view, "#band-form")
    end

    test "Pastor acessa o formulário", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/bands/new")
      assert has_element?(view, "#band-form")
    end

    test "Líder de Banda tem o acesso negado ao criar uma nova banda", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})

      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/bands/new")
      assert flash["error"] =~ "não tem permissão"
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/bands/new")
      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/bands/new")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "cadastro de banda" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, worship_leader_fixture()), leader: member_fixture()}
    end

    test "cadastra a banda com nome e líder designado", %{conn: conn, leader: leader} do
      {:ok, view, _html} = live(conn, ~p"/bands/new")

      assert {:ok, _view, html} =
               view
               |> form("#band-form",
                 band: %{
                   name: "Banda Jovem",
                   description: "Culto de domingo à noite.",
                   leader_id: leader.id
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands")

      assert html =~ "Banda Jovem cadastrada."

      assert [band] = Bands.list_bands()
      assert band.name == "Banda Jovem"
      assert band.leader_id == leader.id
    end

    test "mostra erro quando falta o nome", %{conn: conn, leader: leader} do
      {:ok, view, _html} = live(conn, ~p"/bands/new")

      html =
        view
        |> form("#band-form", band: %{name: "", leader_id: leader.id})
        |> render_submit()

      assert html =~ "informe o nome da banda"
      assert Bands.list_bands() == []
    end

    test "mostra erro quando nenhum líder é escolhido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bands/new")

      html =
        view
        |> form("#band-form", band: %{name: "Banda Sem Líder", leader_id: ""})
        |> render_submit()

      assert html =~ "escolha o Líder de Banda"
      assert Bands.list_bands() == []
    end

    test "oferece apenas usuários com conta ativa como líder", %{conn: conn, leader: leader} do
      pendente = user_fixture(%{name: "Pessoa Pendente", confirmed_at: nil})

      {:ok, _view, html} = live(conn, ~p"/bands/new")

      assert html =~ leader.name
      refute html =~ pendente.name
    end
  end

  describe "edição de banda" do
    test "Líder de Louvor edita qualquer banda", %{conn: conn} do
      band = band_fixture(%{name: "Banda Antiga"})
      conn = log_in_user(conn, worship_leader_fixture())

      {:ok, view, html} = live(conn, ~p"/bands/#{band.id}/edit")
      assert html =~ "Banda Antiga"

      assert {:ok, _view, html} =
               view
               |> form("#band-form", band: %{name: "Banda Renovada"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands")

      assert html =~ "Banda Renovada atualizada."
      assert Bands.get_band(band.id).name == "Banda Renovada"
    end

    test "Líder de Banda edita a própria banda", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda do Líder"})
      conn = log_in_user(conn, leader)

      {:ok, view, _html} = live(conn, ~p"/bands/#{band.id}/edit")

      view
      |> form("#band-form", band: %{name: "Banda do Líder", description: "Nova descrição"})
      |> render_submit()

      assert Bands.get_band(band.id).description == "Nova descrição"
    end

    test "Líder de Banda não edita banda de outro líder", %{conn: conn} do
      band = band_fixture()
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(conn, ~p"/bands/#{band.id}/edit")

      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      band = band_fixture()

      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, ~p"/bands/#{band.id}/edit")

      assert flash["error"] =~ "precisa entrar"
    end

    test "banda inexistente redireciona com aviso", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} = live(conn, ~p"/bands/0/edit")
      assert flash["error"] =~ "não encontrada"
    end
  end
end
