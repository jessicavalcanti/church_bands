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

  # As sete que a migration cadastra. Aparecem em toda contagem de tags, e é
  # de propósito: o sistema não nasce sem vocabulário nenhum.
  @iniciais ["Adoração", "Celebração", "Louvor", "Natal", "Oferta", "Páscoa", "Santa Ceia"]

  describe "lista de tags" do
    test "as sete iniciais nascem cadastradas, em ordem alfabética" do
      assert Enum.map(Repertoire.list_tags(), & &1.name) == @iniciais
    end

    test "a tag acentuada fica no lugar em que se lê" do
      tag_fixture(%{name: "Ângelus"})

      nomes = Enum.map(Repertoire.list_tags(), & &1.name)

      assert nomes == ["Adoração", "Ângelus" | List.delete(@iniciais, "Adoração")]
    end

    test "cada tag diz em quantas músicas está" do
      natal = tag_fixture(%{name: "Natalino"})
      oferta = tag_fixture(%{name: "Ofertório"})
      tag_fixture(%{name: "Ninguém usa"})

      song_fixture(%{tags: [natal, oferta]})
      song_fixture(%{tags: [natal]})
      song_fixture(%{tags: [natal]})

      contagens = Map.new(Repertoire.list_tags(), &{&1.name, &1.song_count})

      assert contagens["Natalino"] == 3
      assert contagens["Ofertório"] == 1
      assert contagens["Ninguém usa"] == 0
    end
  end

  describe "busca de tag pelo id" do
    test "acha pelo id, inclusive em string, que é como ele chega da rota" do
      tag = tag_fixture()

      assert Repertoire.get_tag(tag.id).id == tag.id
      assert Repertoire.get_tag(to_string(tag.id)).id == tag.id
    end

    test "devolve nil para id que não existe e para o que nem é id" do
      assert Repertoire.get_tag(0) == nil
      assert Repertoire.get_tag("tag-nenhuma") == nil
    end
  end

  describe "cadastro de tag" do
    test "cadastra a tag com o nome aparado" do
      assert {:ok, tag} = Repertoire.create_tag(%{name: "  Ministração  "})
      assert tag.name == "Ministração"
    end

    test "recusa tag sem nome" do
      assert {:error, changeset} = Repertoire.create_tag(%{name: "   "})
      assert %{name: ["informe o nome da tag"]} = errors_on(changeset)
    end

    test "recusa nome com menos de 2 caracteres" do
      assert {:error, changeset} = Repertoire.create_tag(%{name: "N"})
      assert %{name: ["precisa ter entre 2 e 40 caracteres"]} = errors_on(changeset)
    end

    test "recusa nome com mais de 40 caracteres" do
      assert {:error, changeset} = Repertoire.create_tag(%{name: String.duplicate("a", 41)})
      assert %{name: ["precisa ter entre 2 e 40 caracteres"]} = errors_on(changeset)
    end

    # "Natal" e "natal" são a mesma tag para quem marca uma música: deixar as
    # duas existirem faria o filtro da US 2.5 achar metade das músicas.
    test "recusa nome repetido, sem distinguir maiúsculas" do
      assert {:error, changeset} = Repertoire.create_tag(%{name: "natal"})
      assert %{name: ["já existe uma tag com esse nome"]} = errors_on(changeset)
    end

    test "recusa nome repetido, sem distinguir acento" do
      tag_fixture(%{name: "Ministração"})

      assert {:error, changeset} = Repertoire.create_tag(%{name: "Ministracao"})
      assert %{name: ["já existe uma tag com esse nome"]} = errors_on(changeset)
    end
  end

  describe "renomear tag" do
    test "renomeia, e as músicas que a usam passam a mostrar o nome novo" do
      tag = tag_fixture(%{name: "Louvor congregacional"})
      song = song_fixture(%{tags: [tag]})

      assert {:ok, _tag} = Repertoire.update_tag(tag, %{name: "Congregacional"})

      assert [marcada] = Repertoire.get_song(song.id).tags
      assert marcada.name == "Congregacional"
    end

    # O índice compara a linha com as outras, e a linha renomeada é ela mesma:
    # corrigir a própria grafia não pode esbarrar em si.
    test "corrigir a grafia da própria tag não colide consigo mesma" do
      tag = tag_fixture(%{name: "Ministracao"})

      assert {:ok, tag} = Repertoire.update_tag(tag, %{name: "Ministração"})
      assert tag.name == "Ministração"
    end

    test "recusa renomear para o nome de outra tag" do
      tag = tag_fixture(%{name: "Ministração"})

      assert {:error, changeset} = Repertoire.update_tag(tag, %{name: "natal"})
      assert %{name: ["já existe uma tag com esse nome"]} = errors_on(changeset)
    end
  end

  describe "exclusão de tag" do
    test "exclui a tag que nenhuma música usa" do
      tag = tag_fixture()

      assert {:ok, _tag} = Repertoire.delete_tag(tag)
      assert Repertoire.get_tag(tag.id) == nil
    end

    test "recusa excluir tag em uso, dizendo em quantas músicas ela está" do
      tag = tag_fixture()
      for _ <- 1..3, do: song_fixture(%{tags: [tag]})

      assert {:error, {:in_use, 3}} = Repertoire.delete_tag(tag)
      assert Repertoire.get_tag(tag.id).id == tag.id
    end
  end

  describe "change_tag/2" do
    test "devolve o changeset que alimenta o formulário" do
      assert %Ecto.Changeset{} = Repertoire.change_tag()

      tag = tag_fixture(%{name: "Ministração"})
      assert Repertoire.change_tag(tag).data.name == "Ministração"
    end
  end

  describe "tags marcadas na música" do
    test "cadastra a música já com as tags marcadas" do
      louvor = tag_fixture(%{name: "Louvor A"})
      natal = tag_fixture(%{name: "Natal A"})

      song = song_fixture(%{title: "Noite Feliz", tags: [louvor, natal]})

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor A", "Natal A"]
    end

    test "cadastra a música sem tag nenhuma" do
      song = song_fixture(%{title: "Oceanos"})

      assert Repertoire.get_song(song.id).tags == []
    end

    test "desmarcar uma tag tira só a marcação, e a tag continua existindo" do
      louvor = tag_fixture(%{name: "Louvor B"})
      natal = tag_fixture(%{name: "Natal B"})
      song = song_fixture(%{tags: [louvor, natal]})

      assert {:ok, _song} = Repertoire.update_song(song, %{"tag_ids" => [louvor.id]})

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor B"]
      assert Repertoire.get_tag(natal.id).name == "Natal B"
    end

    test "marcar tudo de novo com a lista vazia deixa a música sem tags" do
      song = song_fixture(%{tags: [tag_fixture()]})

      assert {:ok, _song} = Repertoire.update_song(song, %{"tag_ids" => []})
      assert Repertoire.get_song(song.id).tags == []
    end

    # É o que permite corrigir o título de uma música por um caminho que não
    # fala de tags sem desmarcar as que ela tem.
    test "atualizar sem falar de tags não mexe nas que a música já tem" do
      tag = tag_fixture(%{name: "Louvor C"})
      song = song_fixture(%{tags: [tag]})

      assert {:ok, _song} = Repertoire.update_song(song, %{"title" => "Outro título"})

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor C"]
    end

    # Pela mesma razão de `ChurchBands.RouteId`: o id chega da tela como texto,
    # e texto é o que alguém pode ter escrito.
    test "aceita id de tag em string, que é como ele chega da tela" do
      tag = tag_fixture(%{name: "Louvor D"})

      song = song_fixture(%{tag_ids: [to_string(tag.id)]})

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == ["Louvor D"]
    end

    test "id de tag que não existe não vira marcação" do
      song = song_fixture(%{tag_ids: [0, "tag-nenhuma", nil]})

      assert Repertoire.get_song(song.id).tags == []
    end

    test "as tags da música vêm em ordem alfabética, na lista e no cadastro" do
      zelo = tag_fixture(%{name: "Zelo"})
      angelus = tag_fixture(%{name: "Ângelus"})
      alegria = tag_fixture(%{name: "Alegria"})

      song = song_fixture(%{tags: [zelo, angelus, alegria]})

      esperado = ["Alegria", "Ângelus", "Zelo"]

      assert Enum.map(Repertoire.get_song(song.id).tags, & &1.name) == esperado

      assert [%{tags: tags}] = Enum.filter(Repertoire.list_songs(), &(&1.id == song.id))
      assert Enum.map(tags, & &1.name) == esperado
    end

    test "excluir a música leva as marcações dela e deixa as tags de pé" do
      tag = tag_fixture()
      song = song_fixture(%{tags: [tag]})

      assert {:ok, _song} = Repertoire.delete_song(song)

      assert Repertoire.get_song(song.id) == nil
      assert Enum.find(Repertoire.list_tags(), &(&1.id == tag.id)).song_count == 0
    end
  end
end
