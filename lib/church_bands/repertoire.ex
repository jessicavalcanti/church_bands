defmodule ChurchBands.Repertoire do
  @moduledoc """
  Contexto do repertório musical: o catálogo central de músicas (US 2.1), as
  tags temáticas com que elas são marcadas (US 2.7) e o repertório de cada
  banda (US 2.2).

  Autorização: cadastrar, editar e excluir música do catálogo é exclusivo de
  Pastor e Líder de Louvor. `manage_songs?/1` é a fonte única dessa regra —
  o menu a consulta para mostrar o item, e o router a aplica de verdade. As
  tags moram em `/admin` porque a tela delas é a única do catálogo que **não**
  abre para leitura ampla: marcar aparece para todos, gerenciar não.

  Quem monta o repertório de uma banda é outra pergunta, e ela é da banda e não
  do catálogo: quem responde é `ChurchBands.Bands.manage_repertoire?/2`, ao
  lado das outras permissões por banda.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Bands.Band
  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Repertoire.Song
  alias ChurchBands.Repertoire.Tag
  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Sorting

  # A comparação de títulos parecidos, num lugar só. O limiar é explícito na
  # consulta, e não o operador `%` do pg_trgm, que lê o GUC
  # `pg_trgm.similarity_threshold` — com ele, o resultado dependeria da
  # configuração do banco em que a suíte roda.
  @similarity_threshold 0.3
  @similar_limit 5
  @minimum_length 3

  # A busca do catálogo (US 2.5) começa em duas letras. Uma letra só casaria
  # com quase tudo — filtrar por ela custa a consulta e não estreita nada.
  @minimum_search_length 2

  # Os status que o filtro do repertório aceita por nome (US 2.6). O `:all` e o
  # `nil` não estão aqui: eles não filtram por um status, dizem *quanto* mostrar.
  @statuses BandRepertoire.statuses()

  ## Autorização

  @doc """
  `true` para quem cuida do catálogo de músicas: Pastor e Líder de Louvor.
  """
  def manage_songs?(user), do: Accounts.full_access?(user)

  ## Catálogo

  @doc """
  Lista o catálogo em ordem alfabética de título, cada música com as tags que a
  marcam (US 2.7).

  `filters` aceita `:search` e `:tag_id`, e **é aqui que se decide o que conta
  como filtro** — termo em branco, termo com menos de
  #{@minimum_search_length} caracteres e `tag_id` nulo são "sem filtro". A tela
  não repete essa regra; ela pergunta com `filtering?/1`.

  A busca casa por **conter** ou por **similaridade trigrama** de pelo menos
  #{@similarity_threshold}, sobre o título e sobre o artista. As duas medidas
  fazem trabalhos diferentes: "conter" resolve quem digita um pedaço do título,
  e o trigrama alcança o acento que faltou e o dedo que escorregou. Diferente
  do aviso de parecidas de `find_similar_songs/2`, aqui não há limite de
  resultados — quem busca quer a lista, não uma amostra.

  O artista entra na comparação **sem `coalesce`**: música sem artista tem
  `NULL` ali, `NULL` não casa com nada, e é exatamente esse o resultado
  desejado. Envolver a coluna faria a expressão deixar de casar com a do índice
  `songs_artist_trgm_idx`.

  A ordem alfabética sai de `ChurchBands.Sorting`, e não de um `ORDER BY`
  (DT-13): quem ordena no banco é a collation, ela muda com o locale de quem o
  subiu, e o mesmo catálogo aparecia em ordens diferentes conforme o ambiente —
  "Ângelus" caindo entre "André" e "Bruno" numa máquina e depois do "Z" no
  container do CI. A US 2.8 fez essa troca nas listas que ordenam por `name`, e
  esta ficou de fora por ordenar por `title`.

  O desempate por `id` é o que torna a ordem determinística quando duas músicas
  têm o mesmo título — e o catálogo permite isso de propósito (US 2.1).
  """
  def list_songs(filters \\ %{}) do
    from(s in Song, as: :song)
    |> filter_by_search(filters[:search])
    |> filter_by_tag(filters[:tag_id])
    |> with_band_count()
    |> Repo.all()
    |> Repo.preload(:tags)
    |> Enum.map(&sort_tags/1)
    |> Enum.sort_by(&{Sorting.key(&1.title), &1.id})
  end

  # Em quantas bandas cada música está (US 2.2), no mesmo `left_join` da
  # consulta — e não numa pergunta por linha da lista, que é o que a coluna
  # nova custaria se saísse de um `Enum.map`.
  #
  # O `group_by` pela chave primária é o que permite selecionar a música
  # inteira ao lado da contagem, como em `Bands.list_instruments/0`. O
  # `inner_join` de `filter_by_tag/2` não atrapalha a conta: o índice único de
  # `song_tags` garante uma linha por par, então ele não multiplica nada.
  defp with_band_count(query) do
    from(s in query,
      left_join: r in assoc(s, :band_repertoires),
      group_by: s.id,
      select: %{s | band_count: count(r.id)}
    )
  end

  @doc """
  `true` quando `filters` estreita a lista de verdade.

  É o que separa os dois estados vazios da tela: catálogo sem música nenhuma
  diz uma coisa, busca que não achou nada diz outra. A pergunta é "houve
  filtro?", e não "a lista veio vazia?" — quem sabe responder é quem aplica o
  filtro.
  """
  def filtering?(filters) do
    not is_nil(search_term(filters[:search])) or not is_nil(filters[:tag_id])
  end

  # Termo que não filtra vira `nil` num lugar só, e some das duas pontas.
  defp search_term(search) do
    case String.trim(to_string(search)) do
      term when byte_size(term) == 0 -> nil
      term -> if String.length(term) < @minimum_search_length, do: nil, else: term
    end
  end

  # A cláusula casa pelo binding **nomeado** `:song`, e não pela posição: quem a
  # chama ora tem a música na posição 0 (o catálogo), ora na 1 (o repertório da
  # banda, que parte do vínculo). O nome é o que permite a mesma regra de busca
  # servir aos dois — a US 2.6 reaproveitou esta função em vez de copiá-la.
  defp filter_by_search(query, search) do
    case search_term(search) do
      nil ->
        query

      term ->
        pattern = "%#{escape_like(term)}%"

        where(
          query,
          [song: s],
          fragment(
            "immutable_unaccent(lower(?)) LIKE immutable_unaccent(lower(?))",
            s.title,
            ^pattern
          ) or
            fragment(
              "immutable_unaccent(lower(?)) LIKE immutable_unaccent(lower(?))",
              s.artist,
              ^pattern
            ) or
            fragment(
              "similarity(immutable_unaccent(lower(?)), immutable_unaccent(lower(?))) >= ?",
              s.title,
              ^term,
              ^@similarity_threshold
            ) or
            fragment(
              "similarity(immutable_unaccent(lower(?)), immutable_unaccent(lower(?))) >= ?",
              s.artist,
              ^term,
              ^@similarity_threshold
            )
        )
    end
  end

  # `%` e `_` digitados na busca são texto, não curinga — o mesmo cuidado que
  # `ChurchBands.Accounts.User.search/2` toma.
  defp escape_like(term), do: String.replace(term, ~r/([\\%_])/, "\\\\\\1")

  # O índice único de `song_tags` garante uma linha por par, então o `join`
  # não multiplica música nenhuma e não precisa de `distinct`.
  defp filter_by_tag(query, nil), do: query

  defp filter_by_tag(query, tag_id) do
    join(query, :inner, [s], st in "song_tags", on: st.song_id == s.id and st.tag_id == ^tag_id)
  end

  @doc """
  Busca uma música pelo id, ou `nil`.

  Como `Bands.get_band/1`, aceita id em string (que é como ele chega da rota)
  e devolve `nil` para o que não for um id, em vez de estourar.
  """
  def get_song(id) when is_binary(id), do: RouteId.get(id, &get_song/1)

  def get_song(id) when is_integer(id) do
    case Repo.get(Song, id) do
      nil -> nil
      song -> song |> Repo.preload(:tags) |> sort_tags()
    end
  end

  @doc """
  Cadastra uma música no catálogo, com as tags marcadas no formulário.
  """
  def create_song(attrs) do
    # A associação precisa estar carregada para o `put_assoc/4`, e a música que
    # ainda não existe não tem o que carregar: nasce marcada como vazia.
    %Song{tags: []}
    |> Song.changeset(attrs)
    |> put_song_tags(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza uma música, inclusive as tags marcadas nela.
  """
  def update_song(%Song{} = song, attrs) do
    song
    |> Repo.preload(:tags)
    |> Song.changeset(attrs)
    |> put_song_tags(attrs)
    |> Repo.update()
  end

  @doc """
  Exclui uma música do catálogo que nenhuma banda toca.

  Devolve `{:error, {:in_use, band_names}}` quando a música está em algum
  repertório (US 2.2), com os nomes das bandas em ordem alfabética. **Os nomes,
  e não a contagem**, porque a saída de quem quer excluir é remover a música do
  repertório dessas bandas (US 2.4), e para isso é preciso saber quais são.
  Quem decide quantos nomes cabem na frase é a tela, não o contexto.

  As marcações da música que sai vão junto, pelo `on_delete: :delete_all` de
  `song_tags`; as tags em si continuam existindo, só com uma música a menos na
  conta.
  """
  def delete_song(%Song{} = song) do
    case bands_with_song(song) do
      [] -> Repo.delete(song)
      names -> {:error, {:in_use, names}}
    end
  end

  defp bands_with_song(%Song{id: id}) do
    from(r in BandRepertoire,
      join: b in assoc(r, :band),
      where: r.song_id == ^id,
      select: b.name
    )
    |> Repo.all()
    |> Enum.sort_by(&Sorting.key/1)
  end

  @doc """
  Changeset para alimentar o formulário de música.
  """
  def change_song(%Song{} = song \\ %Song{}, attrs \\ %{}) do
    Song.changeset(song, attrs)
  end

  @doc """
  As músicas já cadastradas com título parecido com `title`, das mais
  parecidas para as menos.

  É o que sustenta o aviso de duplicata do formulário: o catálogo **não**
  bloqueia título repetido, então quem cadastra precisa ver o que já existe
  para decidir se é a mesma música.

  "Parecido" é similaridade trigrama de pelo menos #{@similarity_threshold}
  sobre o título em minúsculas e sem acento — uma medida só, que cobre a
  diferença de acento *e* o erro de digitação: "Grande e o Senhôr" acha
  "Grande é o Senhor". A comparação é só do título; o artista aparece na tela
  para ajudar a julgar, mas é opcional e não serviria de desempate confiável.

  `exclude_id` tira uma música do resultado — é o que impede a música em
  edição de aparecer como parecida de si mesma. **Não tem valor padrão**: o
  formulário sempre sabe qual dos dois casos é o dele, e passa `nil` no
  cadastro.

  Devolve `[]` para menos de #{@minimum_length} caracteres, e no máximo
  #{@similar_limit} resultados. O desempate por título em ordem alfabética é o
  que torna o resultado estável quando várias empatam na similaridade, e o
  desempate por `id` faz o mesmo quando duas se chamam igual — o catálogo
  permite isso de propósito (US 2.1).

  **A ordem inteira é do Elixir, e não de um `ORDER BY` (DT-13)**, pela mesma
  razão de `list_songs/1`: quem ordena no banco é a collation, ela muda com o
  locale de quem o subiu, e o desempate alfabético saía diferente conforme o
  ambiente. Por isso a similaridade é **selecionada junto** com a música — é
  ela o critério principal, e ordenar fora do banco exige tê-la na mão.

  O corte em #{@similar_limit} também passou para cá, e é o que faz o
  desempate valer: cortando no banco, os cinco que sobrariam de um empate
  seriam escolhidos pela collation antes de o Elixir ter o que reordenar. O
  `where` de similaridade continua sendo quem estreita — o que chega em memória
  é o que já era parecido, não o catálogo inteiro.
  """
  def find_similar_songs(title, exclude_id) when is_binary(title) do
    title = String.trim(title)

    if String.length(title) < @minimum_length do
      []
    else
      Song
      |> where(
        [s],
        fragment(
          "similarity(immutable_unaccent(lower(?)), immutable_unaccent(lower(?))) >= ?",
          s.title,
          ^title,
          ^@similarity_threshold
        )
      )
      |> exclude_song(exclude_id)
      |> select(
        [s],
        {s,
         fragment(
           "similarity(immutable_unaccent(lower(?)), immutable_unaccent(lower(?)))",
           s.title,
           ^title
         )}
      )
      |> Repo.all()
      |> Enum.sort_by(fn {song, similarity} ->
        {-similarity, Sorting.key(song.title), song.id}
      end)
      |> Enum.take(@similar_limit)
      |> Enum.map(fn {song, _similarity} -> song end)
    end
  end

  # Só a edição exclui alguém: no cadastro não existe música própria para
  # deixar de fora.
  defp exclude_song(query, nil), do: query
  defp exclude_song(query, id), do: where(query, [s], s.id != ^id)

  ## Tags

  @doc """
  As tags do grupo em ordem alfabética, com quantas músicas usam cada uma em
  `:song_count`.

  A contagem sai do mesmo `left_join` da consulta, e não de uma pergunta por
  linha: é ela que decide se dá para excluir e é ela que escreve a recusa.
  """
  def list_tags do
    from(t in Tag,
      left_join: s in assoc(t, :songs),
      group_by: t.id,
      select: %{t | song_count: count(s.id)}
    )
    |> Repo.all()
    |> Sorting.by_name()
  end

  @doc """
  Busca uma tag pelo id, ou `nil`. Aceita id em string, como `get_song/1`.
  """
  def get_tag(id) when is_binary(id), do: RouteId.get(id, &get_tag/1)

  def get_tag(id) when is_integer(id), do: Repo.get(Tag, id)

  @doc """
  Cadastra uma tag.
  """
  def create_tag(attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Renomeia uma tag.

  Vale para todas as músicas que a usam de uma vez — não existe versão antiga
  do nome, porque a marcação aponta para a linha e não copia o texto.
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Exclui uma tag que nenhuma música usa.

  Devolve `{:error, {:in_use, count}}` quando há músicas marcadas com ela — a
  contagem é consultada antes, e é ela que produz a mensagem que manda
  desmarcar primeiro. Não existe `foreign_key_constraint` de rede aqui: com a
  contagem consultada, o erro do banco seria um ramo que nenhum teste alcança.
  """
  def delete_tag(%Tag{} = tag) do
    case count_tag_songs(tag) do
      0 -> Repo.delete(tag)
      count -> {:error, {:in_use, count}}
    end
  end

  @doc """
  Changeset para alimentar o formulário de tag.
  """
  def change_tag(%Tag{} = tag \\ %Tag{}, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end

  defp count_tag_songs(%Tag{id: id}) do
    Repo.aggregate(from(st in "song_tags", where: st.tag_id == ^id), :count)
  end

  ## Repertório da banda

  @doc """
  O repertório de `band` em ordem alfabética de título, cada linha com a música
  e as tags dela pré-carregadas.

  `filters` aceita `:status` e `:search` (US 2.6):

    * `status` **nulo é o padrão da tela, não "sem filtro"**: mostra o que está
      em aprendizado e o que está pronto, escondendo o arquivado. Arquivar é
      como se tira uma música da frente sem perder o registro (US 2.3), então
      ela não polui a lista do dia a dia. Quem quer ver tudo pede `:all`;
      quem quer um estado só pede o átomo dele
    * `search` passa pelo mesmo `filter_by_search/2` do catálogo (US 2.5), agora
      sobre a música do vínculo — a regra fica num lugar só. A busca é
      **dentro do repertório desta banda**: música que a banda não tem não
      aparece, mesmo estando no catálogo

  A ordem sai de `ChurchBands.Sorting`, e não de um `ORDER BY` (DT-13), pela
  mesma razão do catálogo: quem ordena no banco é a collation, e ela muda com o
  locale de quem o subiu. O desempate por id da música é o que torna a ordem
  determinística quando duas se chamam igual — o catálogo permite isso de
  propósito (US 2.1).
  """
  def list_band_repertoire(band, filters \\ %{})

  def list_band_repertoire(%Band{} = band, filters), do: list_band_repertoire(band.id, filters)

  def list_band_repertoire(band_id, filters) when is_integer(band_id) do
    from(r in BandRepertoire,
      as: :entry,
      join: s in assoc(r, :song),
      as: :song,
      where: r.band_id == ^band_id,
      preload: [song: s]
    )
    |> filter_by_status(filters[:status])
    |> filter_by_search(filters[:search])
    |> Repo.all()
    # As tags saem numa consulta a mais, e não numa por linha: é o mesmo
    # `Repo.preload/2` do catálogo, sobre a música de cada vínculo.
    |> Repo.preload(song: :tags)
    |> Enum.map(&%{&1 | song: sort_tags(&1.song)})
    |> Enum.sort_by(&{Sorting.key(&1.song.title), &1.song.id})
  end

  # O arquivado só aparece quando alguém o pede — por nome ou pedindo tudo.
  defp filter_by_status(query, nil),
    do: where(query, [entry: r], r.status in [:learning, :ready])

  defp filter_by_status(query, :all), do: query

  defp filter_by_status(query, status) when status in @statuses,
    do: where(query, [entry: r], r.status == ^status)

  @doc """
  `true` quando `filters` estreita o repertório de verdade.

  É o irmão de `filtering?/1` para a tela do repertório (US 2.6), e separa os
  mesmos dois estados vazios: banda que ainda não montou nada diz uma coisa,
  busca que não achou nada diz outra. Repare que **status nulo não é filtro** —
  é o padrão da tela, e uma banda cujas músicas estão todas arquivadas cai no
  vazio de "ainda não tem repertório", que é o que se quer dizer a quem abre.
  """
  def filtering_repertoire?(filters) do
    not is_nil(search_term(filters[:search])) or not is_nil(filters[:status])
  end

  @doc """
  As músicas que ainda podem entrar no repertório de `band`: o catálogo menos o
  que a banda já tem, em ordem alfabética.

  Espelha `Bands.list_member_candidates/2`, e por isso devolve **o catálogo
  inteiro** quando não há busca: a lista completa serve para escolher olhando, e
  a busca só a estreita. `search` passa pelo mesmo `filter_by_search/2` de
  `list_songs/1` — a regra da busca do catálogo (US 2.5) fica num lugar só,
  reaproveitada e não copiada.

  Estar no repertório de outra banda não tira ninguém daqui: a mesma música toca
  em quantas bandas for, com tom próprio em cada uma. Estar no repertório
  **desta**, sim, tira — o vínculo é único por banda.
  """
  def list_repertoire_candidates(%Band{} = band, search \\ nil) do
    from(s in Song, as: :song)
    |> filter_by_search(search)
    |> where(
      [s],
      s.id not in subquery(
        from r in BandRepertoire, where: r.band_id == ^band.id, select: r.song_id
      )
    )
    |> Repo.all()
    |> Enum.sort_by(&{Sorting.key(&1.title), &1.id})
  end

  @doc """
  Vincula uma música do catálogo ao repertório de `band`, no tom de `attrs`.

  Espelha `Bands.add_member/3`: a banda vem do argumento e não de `attrs`, para
  que o formulário não tenha como escolher em qual banda está mexendo — quem
  respondeu por isso foi o hook da rota.

  Nasce **em aprendizado**; mudar o status é a US 2.3. Recusa com
  `{:error, changeset}` a música que já está no repertório da banda, a que não
  existe no catálogo e o tom que não é dos 24.
  """
  def add_song_to_band(%Band{} = band, song_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{"band_id" => band.id, "song_id" => song_id})

    %BandRepertoire{}
    |> BandRepertoire.changeset(attrs)
    |> Repo.insert()
    |> preload_repertoire()
  end

  @doc """
  Busca um vínculo do repertório pelo id, ou `nil`.

  Como `Bands.get_member/1`, aceita id em string — que é como ele chega do
  formulário da linha (US 2.3) — e devolve `nil` para o que não for um id, em
  vez de estourar. A música vem carregada porque é o título dela que a
  confirmação da tela nomeia; a banda, porque é contra o `band_id` dela que
  quem chama confere que o vínculo é mesmo da banda aberta.
  """
  def get_band_song(id) when is_binary(id), do: RouteId.get(id, &get_band_song/1)

  def get_band_song(id) when is_integer(id) do
    BandRepertoire
    |> Repo.get(id)
    |> Repo.preload([:band, :song])
  end

  @doc """
  Muda o tom e o status de uma música no repertório da banda (US 2.3).

  Os dois andam juntos porque é uma linha só que se está corrigindo, e o
  formulário da linha manda os dois valores a cada mudança. O `Ecto.Enum`
  recusa sozinho o tom que não é dos 24 e o status que não existe — inclusive o
  forçado pelo socket —, então não há validação nova a escrever aqui.

  Arquivar **não apaga nada**: a música sai da lista do dia a dia e continua no
  repertório, visível pelo filtro (US 2.6). Não há ordem obrigatória entre os
  status — de arquivada se volta para em aprendizado, e de pronta para trás.
  """
  def update_band_song(%BandRepertoire{} = entry, attrs) do
    entry
    |> BandRepertoire.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Desfaz o vínculo de uma música com o repertório da banda (US 2.4).

  Fecha o ciclo que a US 2.2 abre e a US 2.3 altera, no formato de
  `Bands.remove_member/1`: recebe o vínculo já carregado e apaga só ele. **A
  música continua no catálogo**, disponível para outra banda ou para ser
  vinculada de novo — nada em cascata, `songs`, `tags` e `song_tags` não são
  tocados.

  Removida a última banda que tocava a música, a trava de `delete_song/1`
  deixa de valer para ela: quem consulta as bandas em uso é a própria exclusão,
  a cada chamada, e não um contador guardado na linha.

  Não existe recusa aqui: quem pode remover e se o vínculo é mesmo da banda
  aberta são perguntas de autorização, respondidas antes pela tela — como no
  elenco.
  """
  def remove_song_from_band(%BandRepertoire{} = entry), do: Repo.delete(entry)

  @doc """
  Changeset para alimentar o formulário de repertório.
  """
  def change_band_repertoire(%BandRepertoire{} = entry \\ %BandRepertoire{}, attrs \\ %{}) do
    BandRepertoire.changeset(entry, attrs)
  end

  defp preload_repertoire({:ok, entry}), do: {:ok, Repo.preload(entry, [:band, :song])}
  defp preload_repertoire({:error, _} = error), do: error

  # As tags marcadas chegam do formulário como uma lista de ids, e viram
  # associação com as linhas que existem de verdade: id inventado não vira
  # marcação, e o `put_assoc/4` recebe structs, nunca o que veio da tela.
  #
  # Sem a chave `tag_ids` nos params, a associação não é tocada — é o que
  # permite atualizar uma música por um caminho que não fala de tags sem
  # desmarcar as que ela tem.
  defp put_song_tags(changeset, attrs) do
    case fetch_tag_ids(attrs) do
      :error -> changeset
      {:ok, ids} -> Ecto.Changeset.put_assoc(changeset, :tags, tags_by_ids(ids))
    end
  end

  defp fetch_tag_ids(attrs) when is_map(attrs) do
    case Map.fetch(attrs, "tag_ids") do
      {:ok, ids} -> {:ok, ids}
      :error -> Map.fetch(attrs, :tag_ids)
    end
  end

  defp tags_by_ids(ids) do
    ids = ids |> List.wrap() |> Enum.flat_map(&to_id/1)

    Tag
    |> where([t], t.id in ^ids)
    |> Repo.all()
  end

  # O que não for id é descartado antes da consulta, pela mesma razão de
  # `ChurchBands.RouteId`: a lista chega de `phx-value-id`, e o que vem da tela
  # é texto que alguém pode ter escrito. Descartar aqui é o que faz o id
  # inventado virar "nenhuma tag", e não um `Ecto.Query.CastError`.
  defp to_id(id) when is_integer(id), do: [id]

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> [id]
      _ -> []
    end
  end

  defp to_id(_other), do: []

  # As tags de uma música aparecem como badges lado a lado; sem ordem definida
  # elas mudariam de lugar a cada carga. A mesma ordem alfabética da lista de
  # tags, pela mesma razão de `ChurchBands.Sorting`.
  defp sort_tags(%Song{} = song), do: %{song | tags: Sorting.by_name(song.tags)}
end
