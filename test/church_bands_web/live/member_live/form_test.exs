defmodule ChurchBandsWeb.MemberLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Bands

  defp members_path(band), do: ~p"/bands/#{band.id}/members/new"

  defp edit_member_path(band, member), do: ~p"/bands/#{band.id}/members/#{member.id}/edit"

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

    test "estreitar a busca sem excluir quem foi escolhido não a repete no dropdown", %{
      conn: conn,
      band: band,
      ana: ana
    } do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", %{"search" => "ana", "band_member" => %{"user_id" => ana.id}})
      |> render_change()

      html =
        view
        |> form("#member-form", %{"search" => "ana sou", "band_member" => %{"user_id" => ana.id}})
        |> render_change()

      assert has_element?(view, "#band_member_user_id option[value=\"#{ana.id}\"]")
      # Uma vez só: quem já está entre os candidatos não é acrescentado de novo.
      assert length(Regex.scan(~r/value="#{ana.id}"/, html)) == 1
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
                 band_member: %{
                   user_id: ana.id,
                   type: "instrumentalist",
                   instrument_id: instrument_fixture("Guitarra").id
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Ana Souza entrou na"
      assert html =~ "Guitarra"

      assert [member] = Bands.list_members(band)
      assert member.user_id == ana.id
      assert member.type == :instrumentalist
      assert member.instrument.name == "Guitarra"
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

      refute has_element?(view, "#band_member_instrument_id")
      refute has_element?(view, "#band_member_voice_part")

      view |> form("#member-form", band_member: %{type: "instrumentalist"}) |> render_change()
      assert has_element?(view, "#band_member_instrument_id")
      refute has_element?(view, "#band_member_voice_part")

      view |> form("#member-form", band_member: %{type: "vocalist"}) |> render_change()
      assert has_element?(view, "#band_member_voice_part")
      refute has_element?(view, "#band_member_instrument_id")
    end

    test "instrumentista sem instrumento não é adicionado", %{conn: conn, band: band, ana: ana} do
      {:ok, view, _html} = live(conn, members_path(band))

      view
      |> form("#member-form", band_member: %{user_id: ana.id, type: "instrumentalist"})
      |> render_change()

      html =
        view
        |> form("#member-form",
          band_member: %{user_id: ana.id, type: "instrumentalist", instrument_id: ""}
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

      assert [%{instrument: %{name: "Guitarra"}}] = Bands.list_members(banda_x)
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
                 band_member: %{
                   user_id: leader.id,
                   type: "instrumentalist",
                   instrument_id: instrument_fixture("Violão").id
                 }
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Violão"

      # Com vínculo, ele deixa de ser candidato: já é integrante desta banda.
      {:ok, view, _html} = live(conn, members_path(band))
      refute has_element?(view, "#band_member_user_id option[value=\"#{leader.id}\"]")
    end
  end

  describe "corrigir a função de um integrante (DT-9)" do
    setup %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})
      ana = member_fixture(%{name: "Ana Souza"})

      member =
        band_member_fixture(%{
          band: band,
          user: ana,
          type: :instrumentalist,
          instrument: "Bateria"
        })

      %{conn: log_in_user(conn, leader), band: band, ana: ana, member: member}
    end

    test "o formulário abre com a função que está valendo", %{
      conn: conn,
      band: band,
      member: member
    } do
      {:ok, view, html} = live(conn, edit_member_path(band, member))

      assert has_element?(view, "#member-form")
      assert has_element?(view, "#band_member_instrument_id option[selected]", "Bateria")
      assert has_element?(view, "#band_member_type option[value=\"instrumentalist\"][selected]")
      assert html =~ "Ana Souza"
    end

    test "quem é o músico não se escolhe aqui", %{conn: conn, band: band, member: member} do
      {:ok, view, _html} = live(conn, edit_member_path(band, member))

      # Trocar de pessoa seria remover uma e adicionar outra, não corrigir.
      refute has_element?(view, "#band_member_user_id")
      refute has_element?(view, "#member-search")
      assert has_element?(view, "#member-identity")
    end

    test "corrige o instrumento sem desfazer o vínculo", %{
      conn: conn,
      band: band,
      ana: ana,
      member: member
    } do
      # O cadastro vem antes de abrir a tela: o dropdown é montado no mount, e
      # instrumento cadastrado depois disso ainda não está entre as opções.
      cajon = instrument_fixture("Cajón")
      {:ok, view, _html} = live(conn, edit_member_path(band, member))

      assert {:ok, _show, html} =
               view
               |> form("#member-form",
                 band_member: %{type: "instrumentalist", instrument_id: cajon.id}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Função de Ana Souza atualizada."
      assert html =~ "Cajón"

      # O mesmo vínculo, corrigido — não um novo.
      assert [corrigido] = Bands.list_members(band)
      assert corrigido.id == member.id
      assert corrigido.user_id == ana.id
      assert corrigido.instrument.name == "Cajón"
    end

    test "trocar de instrumentista para vocalista zera o instrumento", %{
      conn: conn,
      band: band,
      member: member
    } do
      {:ok, view, _html} = live(conn, edit_member_path(band, member))

      view
      |> form("#member-form", band_member: %{type: "vocalist"})
      |> render_change()

      assert {:ok, _show, html} =
               view
               |> form("#member-form", band_member: %{type: "vocalist", voice_part: "Contralto"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Vocal — Contralto"

      assert [corrigido] = Bands.list_members(band)
      assert corrigido.type == :vocalist
      assert corrigido.voice_part == "Contralto"
      assert is_nil(corrigido.instrument)
    end

    test "vocalista sem naipe não é salvo", %{conn: conn, band: band, member: member} do
      {:ok, view, _html} = live(conn, edit_member_path(band, member))

      # O campo de naipe só existe depois que a função vira vocalista.
      view
      |> form("#member-form", band_member: %{type: "vocalist"})
      |> render_change()

      html =
        view
        |> form("#member-form", band_member: %{type: "vocalist", voice_part: ""})
        |> render_submit()

      assert html =~ "escolha o naipe"

      assert [intacto] = Bands.list_members(band)
      assert intacto.type == :instrumentalist
      assert intacto.instrument.name == "Bateria"
    end

    test "vínculo do elenco de outra banda não abre por aqui", %{conn: conn, band: band} do
      outra = band_fixture()
      de_fora = band_member_fixture(%{band: outra})

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/bands/#{band.id}/members/#{de_fora.id}/edit")

      assert to == "/bands/#{band.id}"
      assert flash["error"] =~ "Integrante não encontrado."
    end

    test "vínculo inexistente volta para a banda", %{conn: conn, band: band} do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/bands/#{band.id}/members/999999/edit")

      assert to == "/bands/#{band.id}"
      assert flash["error"] =~ "Integrante não encontrado."
    end

    test "músico comum não corrige a função de ninguém", %{band: band, member: member} do
      conn = log_in_user(build_conn(), member_fixture())

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(conn, edit_member_path(band, member))

      assert flash["error"] =~ "não tem permissão"
    end
  end

  describe "o instrumento vem do catálogo (US 2.8)" do
    setup %{conn: conn} do
      leader = member_fixture(%{name: "Carla Líder"})
      band = band_fixture(%{leader: leader})

      %{
        conn: log_in_user(conn, leader),
        band: band,
        ana: member_fixture(%{name: "Ana Souza", email: "ana@exemplo.com"})
      }
    end

    test "o campo é um dropdown do catálogo, não um texto livre", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, members_path(band))

      view |> form("#member-form", band_member: %{type: "instrumentalist"}) |> render_change()

      assert has_element?(view, "select#band_member_instrument_id")
      refute has_element?(view, "input#band_member_instrument_id")
      refute has_element?(view, "datalist#instrument-suggestions")

      opcoes = view |> element("#band_member_instrument_id") |> render()
      assert opcoes =~ "Escolha o instrumento"
      assert opcoes =~ "Bateria"
    end

    # O Líder de Banda não cura o catálogo: oferecer um botão que termina em
    # recusa seria um mau portal, e não dizer nada o deixaria procurando.
    test "o recado diz quem cadastra instrumento novo", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, members_path(band))

      view |> form("#member-form", band_member: %{type: "instrumentalist"}) |> render_change()

      recado = view |> element("#instrument-catalog-hint") |> render()
      assert recado =~ "Pastor ou Líder de Louvor"
      refute has_element?(view, "#new-instrument-button")
    end

    test "instrumento fora do catálogo é recusado, mesmo forçando o evento", %{
      conn: conn,
      band: band,
      ana: ana
    } do
      {:ok, view, _html} = live(conn, members_path(band))

      html =
        render_submit(view, "save", %{
          "band_member" => %{
            "user_id" => to_string(ana.id),
            "type" => "instrumentalist",
            "instrument_id" => "0"
          }
        })

      assert html =~ "escolha um instrumento da lista"
      assert Bands.list_members(band) == []
    end

    test "o instrumento desativado continua escolhido na correção", %{
      conn: conn,
      band: band,
      ana: ana
    } do
      member =
        band_member_fixture(%{
          band: band,
          user: ana,
          type: :instrumentalist,
          instrument: "Trompete"
        })

      {:ok, trompete} =
        member.instrument_id |> Bands.get_instrument() |> Bands.set_instrument_active(false)

      {:ok, view, _html} = live(conn, edit_member_path(band, member))

      assert view |> element("#band_member_instrument_id") |> render() =~ "Trompete"

      # Salvar sem mexer no campo mantém a função de quem já tocava.
      assert {:ok, _show, html} =
               view
               |> form("#member-form",
                 band_member: %{type: "instrumentalist", instrument_id: trompete.id}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/bands/#{band.id}")

      assert html =~ "Trompete"
      assert [intacto] = Bands.list_members(band)
      assert intacto.instrument_id == trompete.id
    end
  end
end
