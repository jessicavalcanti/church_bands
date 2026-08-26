defmodule ChurchBands.Schedule.EventBandSong do
  @moduledoc """
  Uma música no set de uma banda escalada num evento (US 3.6).

  É a linha que responde *o que a banda toca neste culto, em que ordem e em que
  tom*. Pendura-se na escala (`EventBand`), e não no evento: duas bandas no
  mesmo culto tocam coisas diferentes.

  **Aponta para a música do catálogo, não para a linha do repertório.** É o que
  preserva o histórico do que foi tocado quando a banda larga a música depois.
  Em troca, `Repertoire.remove_song_from_band/1` ganhou uma trava: não se tira
  do repertório o que está no set de um evento futuro.

  **O tom é o do repertório da banda, e `key` grava só a exceção daquele
  culto** — a convidada que canta mais grave. Nulo quer dizer "o tom da banda",
  e é por isso que ele é opcional: são duas informações diferentes, e não duas
  cópias da mesma.

  A lista de valores é a **de `BandRepertoire`**, reaproveitada e não repetida:
  são os mesmos 24 tons, e duas listas para manter alinhadas divergiriam no dia
  em que uma delas ganhasse um valor.

  **A posição não é validada contra o conjunto aqui.** Um changeset olha uma
  linha só, e "as posições deste set são 1..N sem buraco" compara linhas
  diferentes: quem responde por isso é `Schedule.reorder_set/2`, numa
  transação.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Repertoire.Song
  alias ChurchBands.Schedule.EventBand

  schema "event_band_songs" do
    field :position, :integer
    field :key, Ecto.Enum, values: BandRepertoire.keys()

    # O tom que a banda toca esta música, vindo do repertório. É virtual porque
    # não é desta linha: quem o traz é o `left_join` de `Schedule.list_set/1`,
    # na mesma consulta. Nulo aqui é o terceiro caso da tela — a música saiu do
    # repertório da banda depois de entrar no set, e não há tom a herdar.
    field :band_key, Ecto.Enum, values: BandRepertoire.keys(), virtual: true

    belongs_to :event_band, EventBand
    belongs_to :song, Song

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset do item do set.

  `key` é opcional de propósito — vazio herda o tom do repertório —, e o
  `Ecto.Enum` recusa sozinho o que não estiver nos 24, inclusive o forçado pelo
  socket.

  A escala vem do socket, nunca do formulário: se ela não existisse, a tela não
  teria aberto. Por isso só a música ganha `assoc_constraint/2` — e a recusa de
  música fora do repertório da banda não é do changeset, que não conhece a
  banda: quem a faz é `Schedule.add_song_to_set/2`.
  """
  def changeset(event_band_song, attrs) do
    event_band_song
    |> cast(attrs, [:event_band_id, :song_id, :position, :key])
    |> validate_required([:song_id], message: "escolha a música")
    |> validate_required([:position, :event_band_id])
    |> assoc_constraint(:song)
  end
end
