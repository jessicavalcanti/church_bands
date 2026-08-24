defmodule ChurchBandsWeb.BandRepertoireLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Repertoire

  defp new_path(band), do: ~p"/bands/#{band.id}/repertoire/new"

  describe "autorização" do
    test "o Líder vincula música na própria banda", %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      {:ok, view, _html} = live(log_in_user(conn, leader), new_path(band))

      assert has_element?(view, "#repertoire-form")
    end

    test "Pastor e Líder de Louvor vinculam em qualquer banda", %{conn: conn} do
      band = band_fixture()

      for user <- [pastor_fixture(), worship_leader_fixture()] do
        {:ok, view, _html} = live(log_in_user(conn, user), new_path(band))

        assert has_element?(view, "#repertoire-form")
      end
    end

    test "o Líder da Banda X é recusado na Banda Y", %{conn: conn} do
      leader_x = member_fixture()
      band_fixture(%{leader: leader_x})
      banda_y = band_fixture()

      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, leader_x), new_path(banda_y))

      assert flash["error"] == "Você não tem permissão para gerenciar o repertório desta banda."
    end

    test "músico comum é recusado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, member_fixture()), new_path(band_fixture()))

      assert flash["error"] == "Você não tem permissão para gerenciar o repertório desta banda."
    end

    test "banda inexistente volta para a lista", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/bands", flash: flash}}} =
               live(log_in_user(conn, pastor_fixture()), ~p"/bands/0/repertoire/new")

      assert flash["error"] == "Banda não encontrada."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, new_path(band_fixture()))

      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "escolher a música" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})

      %{conn: log_in_user(conn, leader), band: band}
    end

    test "a lista traz as músicas do catálogo que a banda ainda não tem", %{
      conn: conn,
      band: band
    } do
      ja_no_repertorio = song_fixture(%{title: "Já no repertório"})
      song_fixture(%{title: "Ainda de fora"})
      band_repertoire_fixture(%{band: band, song: ja_no_repertorio})

      {:ok, _view, html} = live(conn, new_path(band))

      assert html =~ "Ainda de fora"
      refute html =~ "Já no repertório"
    end

    test "o rótulo traz o artista, para distinguir títulos iguais", %{conn: conn, band: band} do
      song_fixture(%{title: "Aleluia", artist: "Gabriela Rocha"})
      song_fixture(%{title: "Aleluia"})

      {:ok, _view, html} = live(conn, new_path(band))

      assert html =~ "Aleluia — Gabriela Rocha"
    end

    test "a busca estreita a lista por título e por artista", %{conn: conn, band: band} do
      song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"})
      song_fixture(%{title: "Oceanos", artist: "Hillsong United"})

      {:ok, view, _html} = live(conn, new_path(band))

      html = view |> form("#repertoire-form", %{"search" => "senhor"}) |> render_change()

      assert html =~ "Grande é o Senhor"
      refute html =~ "Oceanos"
    end

    test "a busca tolera acento que faltou e dedo que escorregou", %{conn: conn, band: band} do
      song_fixture(%{title: "Grande é o Senhor"})

      {:ok, view, _html} = live(conn, new_path(band))

      html =
        view |> form("#repertoire-form", %{"search" => "Grande e o Senhôr"}) |> render_change()

      assert html =~ "Grande é o Senhor"
    end

    test "a música já escolhida continua na lista quando a busca muda", %{
      conn: conn,
      band: band
    } do
      escolhida = song_fixture(%{title: "Grande é o Senhor"})
      song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, new_path(band))

      html =
        view
        |> form("#repertoire-form", %{
          "search" => "oceanos",
          "band_repertoire" => %{"song_id" => to_string(escolhida.id), "key" => "D"}
        })
        |> render_change()

      assert html =~ "Grande é o Senhor"
      assert html =~ "Oceanos"
    end

    test "catálogo inteiro no repertório avisa que não sobrou música", %{
      conn: conn,
      band: band
    } do
      band_repertoire_fixture(%{band: band, song: song_fixture()})

      {:ok, view, html} = live(conn, new_path(band))

      assert has_element?(view, "#no-candidates")
      assert html =~ "Todas as músicas do catálogo já estão no repertório desta banda."
    end

    test "a música escolhida que casa com a busca não aparece duas vezes", %{
      conn: conn,
      band: band
    } do
      escolhida = song_fixture(%{title: "Grande é o Senhor"})

      {:ok, view, _html} = live(conn, new_path(band))

      html =
        view
        |> form("#repertoire-form", %{
          "search" => "grande",
          "band_repertoire" => %{"song_id" => to_string(escolhida.id), "key" => "D"}
        })
        |> render_change()

      assert html
             |> String.split("Grande é o Senhor")
             |> length() == 2
    end

    test "escolher o tom não mexe na lista de músicas", %{conn: conn, band: band} do
      song_fixture(%{title: "Grande é o Senhor"})
      song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, new_path(band))

      view |> form("#repertoire-form", %{"search" => "senhor"}) |> render_change()

      html =
        view
        |> form("#repertoire-form", %{
          "search" => "senhor",
          "band_repertoire" => %{"key" => "D"}
        })
        |> render_change()

      assert html =~ "Grande é o Senhor"
      refute html =~ "Oceanos"
    end

    test "música cadastrada sem artista aparece só com o título", %{conn: conn, band: band} do
      song_fixture(%{title: "Aleluia", artist: ""})

      {:ok, _view, html} = live(conn, new_path(band))

      assert html =~ "Aleluia"
      refute html =~ "Aleluia —"
    end

    test "busca sem resultado avisa com outro texto", %{conn: conn, band: band} do
      song_fixture(%{title: "Oceanos"})

      {:ok, view, _html} = live(conn, new_path(band))

      html = view |> form("#repertoire-form", %{"search" => "zzzz"}) |> render_change()

      assert has_element?(view, "#no-candidates")
      assert html =~ "Nenhuma música do catálogo com esse título ou artista está fora"
    end
  end

  describe "o tom" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      song_fixture(%{title: "Grande é o Senhor"})

      %{conn: log_in_user(conn, leader), band: band}
    end

    test "os 24 tons aparecem agrupados em maiores e menores", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, new_path(band))

      assert has_element?(view, "select#band_repertoire_key optgroup[label='Maiores']")
      assert has_element?(view, "select#band_repertoire_key optgroup[label='Menores']")

      for key <- ~w(C C# D Eb E F F# G Ab A Bb B) do
        assert has_element?(view, "optgroup[label='Maiores'] option[value='#{key}']")
        assert has_element?(view, "optgroup[label='Menores'] option[value='#{key}m']")
      end
    end
  end

  describe "vincular a música" do
    setup %{conn: conn} do
      leader = member_fixture()
      band = band_fixture(%{leader: leader, name: "Banda Jovem"})
      song = song_fixture(%{title: "Grande é o Senhor"})

      %{conn: log_in_user(conn, leader), band: band, song: song}
    end

    test "a música entra no repertório em aprendizado, no tom escolhido", %{
      conn: conn,
      band: band,
      song: song
    } do
      {:ok, view, _html} = live(conn, new_path(band))

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> form("#repertoire-form", %{
                 "band_repertoire" => %{"song_id" => to_string(song.id), "key" => "D"}
               })
               |> render_submit()

      assert path == "/bands/#{band.id}/repertoire"

      assert [entry] = Repertoire.list_band_repertoire(band)
      assert entry.key == :D
      assert entry.status == :learning
      assert entry.song.id == song.id
    end

    test "o repertório mostra a música e a mensagem de sucesso", %{
      conn: conn,
      band: band,
      song: song
    } do
      {:ok, view, _html} = live(conn, new_path(band))

      {:ok, _view, html} =
        view
        |> form("#repertoire-form", %{
          "band_repertoire" => %{"song_id" => to_string(song.id), "key" => "D"}
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/bands/#{band.id}/repertoire")

      assert html =~ "Grande é o Senhor entrou no repertório da Banda Jovem."
      assert html =~ "Grande é o Senhor"
    end

    test "o Pastor vincula música em banda que não é dele", %{conn: conn, song: song} do
      band = band_fixture(%{name: "Banda de Domingo"})

      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), new_path(band))

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#repertoire-form", %{
                 "band_repertoire" => %{"song_id" => to_string(song.id), "key" => "G"}
               })
               |> render_submit()

      assert [%{key: :G}] = Repertoire.list_band_repertoire(band)
    end

    test "sem tom o vínculo não é criado e o campo pede o tom", %{
      conn: conn,
      band: band,
      song: song
    } do
      {:ok, view, _html} = live(conn, new_path(band))

      html =
        view
        |> form("#repertoire-form", %{
          "band_repertoire" => %{"song_id" => to_string(song.id), "key" => ""}
        })
        |> render_submit()

      assert html =~ "escolha o tom"
      assert Repertoire.list_band_repertoire(band) == []
    end

    test "sem música o vínculo não é criado e o campo pede a música", %{
      conn: conn,
      band: band
    } do
      {:ok, view, _html} = live(conn, new_path(band))

      html =
        view
        |> form("#repertoire-form", %{
          "band_repertoire" => %{"song_id" => "", "key" => "D"}
        })
        |> render_submit()

      assert html =~ "escolha a música"
      assert Repertoire.list_band_repertoire(band) == []
    end

    test "forçar uma música já vinculada é recusado na tela", %{
      conn: conn,
      band: band,
      song: song
    } do
      band_repertoire_fixture(%{band: band, song: song, key: "C"})

      {:ok, view, _html} = live(conn, new_path(band))

      html =
        render_submit(view, "save", %{
          "band_repertoire" => %{"song_id" => to_string(song.id), "key" => "G"}
        })

      assert html =~ "já está no repertório desta banda"
      assert [%{key: :C}] = Repertoire.list_band_repertoire(band)
    end

    test "forçar uma música que não existe é recusado", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, new_path(band))

      html =
        render_submit(view, "save", %{"band_repertoire" => %{"song_id" => "0", "key" => "D"}})

      assert html =~ "escolha uma música da lista"
      assert Repertoire.list_band_repertoire(band) == []
    end

    test "cada banda guarda o seu tom para a mesma música", %{
      conn: conn,
      band: band,
      song: song
    } do
      banda_y = band_fixture(%{name: "Banda de Domingo"})
      band_repertoire_fixture(%{band: band, song: song, key: "D"})

      {:ok, view, _html} = live(log_in_user(conn, pastor_fixture()), new_path(banda_y))

      view
      |> form("#repertoire-form", %{
        "band_repertoire" => %{"song_id" => to_string(song.id), "key" => "C"}
      })
      |> render_submit()

      assert [%{key: :D}] = Repertoire.list_band_repertoire(band)
      assert [%{key: :C}] = Repertoire.list_band_repertoire(banda_y)
    end

    test "o botão de voltar leva ao repertório", %{conn: conn, band: band} do
      {:ok, view, _html} = live(conn, new_path(band))

      assert view |> element("#back-to-repertoire") |> render_click() ==
               {:error, {:live_redirect, %{kind: :push, to: "/bands/#{band.id}/repertoire"}}}
    end
  end
end
