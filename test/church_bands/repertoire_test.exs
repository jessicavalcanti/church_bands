defmodule ChurchBands.RepertoireTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.RepertoireFixtures

  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.Song

  describe "quem cuida do catálogo" do
    test "Pastor e Líder de Louvor cuidam do catálogo" do
      assert Repertoire.manage_songs?(pastor_fixture())
      assert Repertoire.manage_songs?(worship_leader_fixture())
    end

    test "músico comum não cuida do catálogo" do
      refute Repertoire.manage_songs?(member_fixture())
    end

    test "visitante não autenticado não cuida do catálogo" do
      refute Repertoire.manage_songs?(nil)
    end
  end

  describe "cadastro de música" do
    test "cadastra com todos os campos preenchidos" do
      assert {:ok, %Song{} = song} =
               Repertoire.create_song(%{
                 title: "Grande é o Senhor",
                 artist: "Adhemar de Campos",
                 bpm: 72,
                 reference_url: "https://youtube.com/watch?v=abc",
                 chord_chart_url: "https://cifraclub.com.br/grande-e-o-senhor"
               })

      assert song.title == "Grande é o Senhor"
      assert song.artist == "Adhemar de Campos"
      assert song.bpm == 72
      assert song.reference_url == "https://youtube.com/watch?v=abc"
      assert song.chord_chart_url == "https://cifraclub.com.br/grande-e-o-senhor"
    end

    test "cadastra só com o título, deixando o resto em branco" do
      assert {:ok, %Song{} = song} = Repertoire.create_song(%{title: "Oceanos"})

      assert song.artist == nil
      assert song.bpm == nil
      assert song.reference_url == nil
      assert song.chord_chart_url == nil
    end

    test "recusa música sem título" do
      assert {:error, changeset} = Repertoire.create_song(%{artist: "Hillsong"})
      assert %{title: ["informe o título da música"]} = errors_on(changeset)
    end

    test "recusa título que é só espaço em branco" do
      assert {:error, changeset} = Repertoire.create_song(%{title: "   "})
      assert %{title: ["informe o título da música"]} = errors_on(changeset)
    end

    test "grava o título sem os espaços das pontas" do
      assert {:ok, song} = Repertoire.create_song(%{title: "  Oceanos  "})
      assert song.title == "Oceanos"
    end

    test "recusa título com mais de 255 caracteres" do
      assert {:error, changeset} = Repertoire.create_song(%{title: String.duplicate("a", 256)})
      assert %{title: ["precisa ter no máximo 255 caracteres"]} = errors_on(changeset)
    end

    test "recusa link de referência que não começa com http" do
      assert {:error, changeset} =
               Repertoire.create_song(%{title: "Oceanos", reference_url: "youtube.com/oceanos"})

      assert %{reference_url: ["precisa começar com http:// ou https://"]} = errors_on(changeset)
    end

    test "recusa link de cifra que não começa com http" do
      assert {:error, changeset} =
               Repertoire.create_song(%{
                 title: "Oceanos",
                 chord_chart_url: "cifraclub.com.br/oceanos"
               })

      assert %{chord_chart_url: ["precisa começar com http:// ou https://"]} =
               errors_on(changeset)
    end

    test "aceita link com http sem s" do
      assert {:ok, song} =
               Repertoire.create_song(%{title: "Oceanos", reference_url: "http://exemplo.com"})

      assert song.reference_url == "http://exemplo.com"
    end

    test "recusa BPM que não é número" do
      assert {:error, changeset} = Repertoire.create_song(%{title: "Oceanos", bpm: "rápido"})
      assert %{bpm: ["is invalid"]} = errors_on(changeset)
    end

    test "o mesmo título pode ser cadastrado duas vezes" do
      assert {:ok, _primeira} = Repertoire.create_song(%{title: "Oceanos"})
      assert {:ok, _segunda} = Repertoire.create_song(%{title: "Oceanos"})

      assert length(Repertoire.list_songs()) == 2
    end
  end

  describe "leitura do catálogo" do
    test "lista as músicas em ordem alfabética de título" do
      song_fixture(%{title: "Ousado Amor"})
      song_fixture(%{title: "Aleluia"})
      song_fixture(%{title: "Grande é o Senhor"})

      assert Enum.map(Repertoire.list_songs(), & &1.title) ==
               ["Aleluia", "Grande é o Senhor", "Ousado Amor"]
    end

    test "o catálogo vazio devolve lista vazia" do
      assert Repertoire.list_songs() == []
    end

    test "busca uma música pelo id" do
      song = song_fixture()
      assert Repertoire.get_song(song.id).id == song.id
    end

    test "busca pelo id que veio da rota, em texto" do
      song = song_fixture()
      assert Repertoire.get_song(to_string(song.id)).id == song.id
    end

    test "devolve nil para id que não existe" do
      refute Repertoire.get_song(999_999)
    end

    test "devolve nil para id que nem é número" do
      refute Repertoire.get_song("inventado")
    end
  end

  describe "edição e exclusão" do
    test "atualiza os dados de uma música" do
      song = song_fixture(%{title: "Oceanos"})

      assert {:ok, atualizada} = Repertoire.update_song(song, %{artist: "Hillsong United"})
      assert atualizada.artist == "Hillsong United"
      assert atualizada.title == "Oceanos"
    end

    test "recusa a edição que apaga o título" do
      song = song_fixture()

      assert {:error, changeset} = Repertoire.update_song(song, %{title: ""})
      assert %{title: ["informe o título da música"]} = errors_on(changeset)
    end

    test "exclui uma música do catálogo" do
      song = song_fixture()

      assert {:ok, _song} = Repertoire.delete_song(song)
      refute Repertoire.get_song(song.id)
    end

    test "o changeset do formulário aceita uma música nova" do
      assert %Ecto.Changeset{} = Repertoire.change_song()
    end
  end

  describe "músicas parecidas" do
    test "acha a música com acento quando o título é digitado sem ele" do
      song_fixture(%{title: "Grande é o Senhor"})

      assert [achada] = Repertoire.find_similar_songs("Grande e o Senhor", nil)
      assert achada.title == "Grande é o Senhor"
    end

    test "acha a música mesmo com erro de digitação e acento trocado" do
      song_fixture(%{title: "Grande é o Senhor"})

      assert [achada] = Repertoire.find_similar_songs("Grande e o Senhôr", nil)
      assert achada.title == "Grande é o Senhor"
    end

    test "não devolve nada quando nenhuma música é parecida" do
      song_fixture(%{title: "Oceanos"})

      assert Repertoire.find_similar_songs("Aleluia", nil) == []
    end

    test "não consulta nada com menos de três caracteres" do
      song_fixture(%{title: "Gr"})

      assert Repertoire.find_similar_songs("Gr", nil) == []
    end

    test "os espaços das pontas não contam para o mínimo de caracteres" do
      song_fixture(%{title: "Gr"})

      assert Repertoire.find_similar_songs("  Gr  ", nil) == []
    end

    test "devolve no máximo cinco, da mais parecida para a menos" do
      for i <- 1..8, do: song_fixture(%{title: "Aleluia #{i}"})

      parecidas = Repertoire.find_similar_songs("Aleluia", nil)

      assert length(parecidas) == 5
    end

    test "desempata pelo título em ordem alfabética" do
      for titulo <- ["Aleluia C", "Aleluia A", "Aleluia B"], do: song_fixture(%{title: titulo})

      assert Enum.map(Repertoire.find_similar_songs("Aleluia", nil), & &1.title) ==
               ["Aleluia A", "Aleluia B", "Aleluia C"]
    end

    test "a música em edição não é parecida consigo mesma" do
      song = song_fixture(%{title: "Grande é o Senhor"})
      outra = song_fixture(%{title: "Grande e o Senhor"})

      assert [achada] = Repertoire.find_similar_songs(song.title, song.id)
      assert achada.id == outra.id
    end

    test "a comparação é só do título, e o artista não entra nela" do
      song_fixture(%{title: "Oceanos", artist: "Hillsong United"})

      assert Repertoire.find_similar_songs("Hillsong United", nil) == []
    end
  end
end
