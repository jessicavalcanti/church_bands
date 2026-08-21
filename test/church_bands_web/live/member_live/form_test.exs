defmodule ChurchBandsWeb.MemberLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  defp members_path(band), do: ~p"/bands/#{band.id}/members/new"

  describe "autorização" do
    test "Líder da banda acessa os integrantes da própria banda", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      conn = log_in_user(conn, leader)

      assert {:ok, view, _html} = live(conn, members_path(band))
      assert has_element?(view, "#member-form")
    end

    test "Pastor e Líder de Louvor acessam qualquer banda", %{conn: conn} do
      band = band_fixture()

      assert {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), members_path(band))
      assert has_element?(view, "#member-form")

      assert {:ok, view, _html} =
               live(log_in_user(conn, worship_leader_fixture()), members_path(band))

      assert has_element?(view, "#member-form")
    end

    test "Líder da Banda X tem o acesso negado na Banda Y", %{conn: conn} do
      leader_x = member_fixture()
      band_fixture(%{leader: leader_x})
      banda_y = band_fixture()

      conn = log_in_user(conn, leader_x)

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(conn, members_path(banda_y))

      assert flash["error"] =~ "não tem permissão"
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(conn, members_path(band_fixture()))

      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, members_path(band_fixture()))

      assert flash["error"] =~ "precisa entrar"
    end

    test "banda inexistente volta para a lista", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(conn, ~p"/bands/0/members/new")

      assert flash["error"] =~ "não encontrada"
    end
  end

  describe "escolher o músico" do
    setup %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})

      %{
        conn: log_in_user(conn, leader),
        band: band,
        leader: leader,
        ana: member_fixture(%{name: "Ana Souza", email: "ana@exemplo.com"})
      }
    end

    test "o dropdown lista os músicos disponíveis", %{
      conn: conn,
      band: band,
      ana: ana,
      leader: leader
    } do
      {:ok, view, html} = live(conn, members_path(band))

      assert html =~ "Ana Souza — ana@exemplo.com"
      assert has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
      assert has_element?(view, "#band_member_user_id option[value=\"#{leader.id}\"]")
    end

    test "quem está em outra banda continua no dropdown", %{conn: conn, band: band, ana: ana} do
      band_member_fixture(%{user: ana})

      {:ok, view, _html} = live(conn, members_path(band))

      assert has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
    end

    test "quem já é integrante desta banda sai do dropdown", %{conn: conn, band: band, ana: ana} do
      band_member_fixture(%{band: band, user: ana})

      {:ok, view, _html} = live(conn, members_path(band))

      refute has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
    end

    test "conta ainda não ativada não entra no dropdown", %{conn: conn, band: band} do
      pendente = user_fixture(%{name: "Pendente Silva", confirmed_at: nil})

      {:ok, view, _html} = live(conn, members_path(band))

      refute has_element?(view, "#band_member_user_id option[value=\"#{pendente.id}\"]")
    end

    test "a busca estreita o dropdown sem escolher ninguém", %{
      conn: conn,
      band: band,
      ana: ana,
      leader: leader
    } do
      {:ok, view, _html} = live(conn, members_path(band))

      view |> form("#member-form", %{"search" => "ana sou"}) |> render_change()

      assert has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
      refute has_element?(view, "#band_member_user_id option[value=\"#{leader.id}\"]")
    end

    test "busca sem resultado explica o motivo", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, members_path(band))

      html = view |> form("#member-form", %{"search" => "zzz"}) |> render_change()

      assert html =~ "Nenhum músico disponível com esse nome ou e-mail"
      assert has_element?(view, "#no-candidates")
    end

    test "quem foi escolhido continua no dropdown mesmo fora da busca", %{
      conn: conn,
      band: band,
      ana: ana
    } do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", %{"search" => "", "band_member" => %{"user_id" => ana.id}})
      |> render_change()

      view
      |> form("#member-form", %{"search" => "carla", "band_member" => %{"user_id" => ana.id}})
      |> render_change()

      assert has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
    end
  end

  describe "adicionar integrante" do
    setup %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})

      %{
        conn: log_in_user(conn, leader),
        band: band,
        leader: leader,
        ana: member_fixture(%{name: "Ana Souza", email: "ana@exemplo.com"})
      }
    end

    test "adiciona um instrumentista escolhido no dropdown", %{conn: conn, band: band, ana: ana} do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", band_member: %{user_id: ana.id, type: "instrumentalist"})
      |> render_change()

      # Adicionar devolve para a banda, onde o elenco mostra quem entrou.
      assert {:ok, _show, html} =
               view
               |> form("#member-form",
                 band_member: %{user_id: ana.id, type: "instrumentalist", instrument: "Guitarra"}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Ana Souza entrou na"
      assert html =~ "Guitarra"

      assert [member] = Bands.list_members(band)
      assert member.user_id == ana.id
      assert member.type == :instrumentalist
      assert member.instrument == "Guitarra"
    end

    test "adiciona vocalista com naipe", %{conn: conn, band: band, ana: ana} do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", band_member: %{user_id: ana.id, type: "vocalist"})
      |> render_change()

      assert {:ok, _show, html} =
               view
               |> form("#member-form",
                 band_member: %{user_id: ana.id, type: "vocalist", voice_part: "Contralto"}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Contralto"
      assert [%{type: :vocalist, voice_part: "Contralto"}] = Bands.list_members(band)
    end

    test "o campo dependente segue a função escolhida", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, members_path(band))

      refute has_element?(view, "#band_member_instrument")
      refute has_element?(view, "#band_member_voice_part")

      view |> form("#member-form", band_member: %{type: "instrumentalist"}) |> render_change()
      assert has_element?(view, "#band_member_instrument")
      refute has_element?(view, "#band_member_voice_part")

      view |> form("#member-form", band_member: %{type: "vocalist"}) |> render_change()
      assert has_element?(view, "#band_member_voice_part")
      refute has_element?(view, "#band_member_instrument")
    end

    test "instrumentista sem instrumento não é adicionado", %{conn: conn, band: band, ana: ana} do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", band_member: %{user_id: ana.id, type: "instrumentalist"})
      |> render_change()

      html =
        view
        |> form("#member-form",
          band_member: %{user_id: ana.id, type: "instrumentalist", instrument: ""}
        )
        |> render_submit()

      assert html =~ "informe o instrumento"
      assert Bands.list_members(band) == []
    end

    test "sem músico escolhido não adiciona", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, members_path(band))

      view |> form("#member-form", band_member: %{type: "vocalist"}) |> render_change()

      html =
        view
        |> form("#member-form", band_member: %{type: "vocalist", voice_part: "Tenor"})
        |> render_submit()

      assert html =~ "escolha o músico"
      assert Bands.list_members(band) == []
    end

    test "o mesmo músico entra em outra banda com função própria", %{conn: conn, ana: ana} do
      leader = member_fixture()
      banda_y = band_fixture(%{leader: leader})
      banda_x = band_fixture()

      band_member_fixture(%{
        band: banda_x,
        user: ana,
        type: :instrumentalist,
        instrument: "Guitarra"
      })

      conn = log_in_user(conn, leader)
      {:ok, view, _html} = live(conn, members_path(banda_y))

      view
      |> form("#member-form", band_member: %{user_id: ana.id, type: "vocalist"})
      |> render_change()

      view
      |> form("#member-form",
        band_member: %{user_id: ana.id, type: "vocalist", voice_part: "Tenor"}
      )
      |> render_submit()

      assert [%{instrument: "Guitarra"}] = Bands.list_members(banda_x)
      assert [%{voice_part: "Tenor"}] = Bands.list_members(banda_y)
    end
  end

  describe "a função do Líder de Banda" do
    test "o líder ainda sem função está no dropdown e sai dele depois", %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      {:ok, view, _html} = live(conn, members_path(band))
      assert has_element?(view, "#band_member_user_id option[value=\"#{leader.id}\"]")

      view
      |> form("#member-form", band_member: %{user_id: leader.id, type: "instrumentalist"})
      |> render_change()

      assert {:ok, _show, html} =
               view
               |> form("#member-form",
                 band_member: %{user_id: leader.id, type: "instrumentalist", instrument: "Violão"}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Violão"

      # Com vínculo, ele deixa de ser candidato: já é integrante desta banda.
      {:ok, view, _html} = live(conn, members_path(band))
      refute has_element?(view, "#band_member_user_id option[value=\"#{leader.id}\"]")
    end
  end
end
