defmodule ChurchBands.Repertoire do
  @moduledoc """
  Contexto do repertório musical: o catálogo central de músicas (US 2.1) e as
  tags temáticas com que elas são marcadas (US 2.7).

  Autorização: cadastrar, editar e excluir música do catálogo é exclusivo de
  Pastor e Líder de Louvor. `manage_songs?/1` é a fonte única dessa regra —
  o menu a consulta para mostrar o item, e o router a aplica de verdade. As
  tags moram em `/admin` porque a tela delas é a única do catálogo que **não**
  abre para leitura ampla: marcar aparece para todos, gerenciar não.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
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
    Song
    |> filter_by_search(filters[:search])
    |> filter_by_tag(filters[:tag_id])
    |> Repo.all()
    |> Repo.preload(:tags)
    |> Enum.map(&sort_tags/1)
    |> Enum.sort_by(&{Sorting.key(&1.title), &1.id})
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

  defp filter_by_search(query, search) do
    case search_term(search) do
      nil ->
        query

      term ->
        pattern = "%#{escape_like(term)}%"

        where(
          query,
          [s],
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
  Exclui uma música do catálogo.

  As marcações dela vão junto, pelo `on_delete: :delete_all` de `song_tags`; as
  tags em si continuam existindo, só com uma música a menos na conta.
  """
  def delete_song(%Song{} = song), do: Repo.delete(song)

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
  que torna o resultado estável quando várias empatam na similaridade.
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
      |> order_by([s],
        desc:
          fragment(
            "similarity(immutable_unaccent(lower(?)), immutable_unaccent(lower(?)))",
            s.title,
            ^title
          ),
        asc: s.title
      )
      |> limit(^@similar_limit)
      |> Repo.all()
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
