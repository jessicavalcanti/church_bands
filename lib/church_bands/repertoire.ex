defmodule ChurchBands.Repertoire do
  @moduledoc """
  Contexto do repertório musical: por enquanto, o catálogo central de músicas
  (US 2.1).

  Autorização: cadastrar, editar e excluir música do catálogo é exclusivo de
  Pastor e Líder de Louvor. `manage_songs?/1` é a fonte única dessa regra —
  o menu a consulta para mostrar o item, e o router a aplica de verdade.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Repertoire.Song
  alias ChurchBands.Repo
  alias ChurchBands.RouteId

  # A comparação de títulos parecidos, num lugar só. O limiar é explícito na
  # consulta, e não o operador `%` do pg_trgm, que lê o GUC
  # `pg_trgm.similarity_threshold` — com ele, o resultado dependeria da
  # configuração do banco em que a suíte roda.
  @similarity_threshold 0.3
  @similar_limit 5
  @minimum_length 3

  ## Autorização

  @doc """
  `true` para quem cuida do catálogo de músicas: Pastor e Líder de Louvor.
  """
  def manage_songs?(user), do: Accounts.full_access?(user)

  ## Catálogo

  @doc """
  Lista as músicas do catálogo em ordem alfabética de título.
  """
  def list_songs do
    Song
    |> order_by(asc: :title)
    |> Repo.all()
  end

  @doc """
  Busca uma música pelo id, ou `nil`.

  Como `Bands.get_band/1`, aceita id em string (que é como ele chega da rota)
  e devolve `nil` para o que não for um id, em vez de estourar.
  """
  def get_song(id) when is_binary(id), do: RouteId.get(id, &get_song/1)

  def get_song(id) when is_integer(id), do: Repo.get(Song, id)

  @doc """
  Cadastra uma música no catálogo.
  """
  def create_song(attrs) do
    %Song{}
    |> Song.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atualiza uma música.
  """
  def update_song(%Song{} = song, attrs) do
    song
    |> Song.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Exclui uma música do catálogo.
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
end
