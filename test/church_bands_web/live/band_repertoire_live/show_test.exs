defmodule ChurchBandsWeb.BandRepertoireLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  defp repertoire_path(band), do: ~p"/bands/#{band.id}/repertoire"

  describe "autorização" do
    test "o Líder abre o repertório da própria banda", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      {:ok, view, _html} = live(log_in_user(conn, leader), repertoire_path(band))

      assert has_element?(view, "#repertoire-empty")
    end

    test "Pastor e Líder de Louvor abrem o repertório de qualquer banda", %{conn: conn} do
      band = band_fixture()

      for user <- [pastor_fixture(), worship_leader_fixture()] do
        {:ok, view, _html} = live(log_in_user(conn, user), repertoire_path(band))

        assert has_element?(view, "#add-repertoire-song")
      end
    end

    test "o Líder da Banda X é recusado no repertório da Banda Y", %{conn: conn} do
      leader_x = member_fixture()
      band_fixture(%{leader: leader_x})
      banda_y = band_fixture()

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, leader_x), repertoire_path(banda_y))

      assert flash["error"] == "Você não tem permissão para gerenciar o repertório desta banda."
    end

    test "o músico comum da banda recebe a mesma recusa", %{conn: conn} do
      band = band_fixture()
      musician = member_fixture()
      band_member_fixture(%{band: band, user: musician})

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, musician), repertoire_path(band))

      assert flash["error"] == "Você não tem permissão para gerenciar o repertório desta banda."
    end

    test "banda inexistente volta para a lista", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, pastor_fixture()), ~p"/bands/0/repertoire")

      assert flash["error"] == "Banda não encontrada."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, repertoire_path(band_fixture()))

      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "a lista do repertório" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})

      %{conn: log_in_user(conn, leader), band: band}
    end

    test "banda sem música diz que o repertório está vazio", %{conn: conn, band: band} do
      {:ok, view, html} = live(conn, repertoire_path(band))

      assert has_element?(view, "#repertoire-empty")
      assert html =~ "Nenhuma música no repertório ainda."
      refute has_element?(view, "#repertoire")
    end

    test "mostra título, artista, tom e status de cada música", %{conn: conn, band: band} do
      song = song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})
      entry = band_repertoire_fixture(%{band: band, song: song, key: "D"})

      {:ok, view, html} = live(conn, repertoire_path(band))

      assert html =~ "Grande é o Senhor"
      assert html =~ "Adhemar de Campos"
      assert view |> element("#repertoire-key-#{entry.id}") |> render() =~ "D"
      assert view |> element("#repertoire-status-#{entry.id}") |> render() =~ "Em aprendizado"
      refute has_element?(view, "#repertoire-empty")
    end

    test "as músicas saem em ordem alfabética de título", %{conn: conn, band: band} do
      for title <- ["Ressuscita-me", "Ágape", "Bondade de Deus"] do
        band_repertoire_fixture(%{band: band, song: song_fixture(%{title: title})})
      end

      {:ok, _view, html} = live(conn, repertoire_path(band))

      assert [{_, agape}, {_, bondade}, {_, ressuscita}] =
               Enum.map(
                 ["Ágape", "Bondade de Deus", "Ressuscita-me"],
                 &{&1, :binary.match(html, &1) |> elem(0)}
               )

      assert agape < bondade and bondade < ressuscita
    end

    test "o status guardado como pronta aparece com o rótulo dele", %{conn: conn, band: band} do
      entry = band_repertoire_fixture(%{band: band, song: song_fixture(), status: :ready})

      {:ok, view, _html} = live(conn, repertoire_path(band))

      assert view |> element("#repertoire-status-#{entry.id}") |> render() =~ "Pronta"
    end

    test "o repertório de uma banda não mostra o da outra", %{conn: conn, band: band} do
      band_repertoire_fixture(%{band: band, song: song_fixture(%{title: "Só da Banda Jovem"})})

      band_repertoire_fixture(%{
        band: band_fixture(),
        song: song_fixture(%{title: "Só da outra banda"})
      })

      {:ok, _view, html} = live(conn, repertoire_path(band))

      assert html =~ "Só da Banda Jovem"
      refute html =~ "Só da outra banda"
    end

    test "o botão de adicionar leva ao formulário de vínculo", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      assert view |> element("#add-repertoire-song") |> render_click() ==
               {:error, {:live_redirect, %{kind: :push, to: "/bands/#{band.id}/repertoire/new"}}}
    end

    test "o botão de voltar leva à tela da banda", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, repertoire_path(band))

      assert view |> element("#back-to-band") |> render_click() ==
               {:error, {:live_redirect, %{kind: :push, to: "/bands/#{band.id}"}}}
    end
  end
end
