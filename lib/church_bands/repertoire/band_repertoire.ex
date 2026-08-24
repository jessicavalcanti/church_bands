defmodule ChurchBands.Repertoire.BandRepertoire do
  @moduledoc """
  Uma música no repertório de uma banda (US 2.2).

  É a linha que liga o catálogo às bandas. A mesma música pode estar em várias
  bandas, e **o tom é de cada uma**: "Grande é o Senhor" em D na Banda Jovem e
  em C na Banda de Domingo são dois registros independentes, como os vínculos
  de `ChurchBands.Bands.BandMember`.

  O tom sai de uma lista fechada de 24 — as 12 notas em maior e em menor —,
  escrita como se lê e como se grava: "D" e "Dm". Não há bemol e sustenido para
  a mesma altura (`Eb` e não `D#`), porque duas grafias da mesma nota dariam
  dois tons diferentes na busca e na tela.

  O status nasce em `:learning`, e desde a US 2.3 quem o muda é a própria linha
  da lista: os três valores se alcançam em qualquer ordem, inclusive de volta.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Bands.Band
  alias ChurchBands.Repertoire.Song

  @major_keys ~w(C C# D Eb E F F# G Ab A Bb B)a
  @minor_keys Enum.map(@major_keys, &String.to_atom("#{&1}m"))
  @keys @major_keys ++ @minor_keys

  @statuses [:learning, :ready, :archived]

  schema "band_repertoires" do
    field :key, Ecto.Enum, values: @keys
    field :status, Ecto.Enum, values: @statuses, default: :learning

    belongs_to :band, Band
    belongs_to :song, Song

    timestamps(type: :utc_datetime)
  end

  @doc """
  Os 24 tons aceitos, maiores antes dos menores.
  """
  def keys, do: @keys

  @doc """
  Os 12 tons maiores, na ordem cromática — é a ordem em que se lê um teclado,
  não a alfabética.
  """
  def major_keys, do: @major_keys

  @doc """
  Os 12 tons menores, na mesma ordem cromática dos maiores.
  """
  def minor_keys, do: @minor_keys

  @doc """
  Os status que uma música pode ter no repertório.
  """
  def statuses, do: @statuses

  @doc """
  Os 24 tons em dois grupos, na ordem cromática de cada um — é como se lê um
  teclado, e não como se lista em ordem alfabética. O `<select>` agrupado é o
  que evita uma lista corrida de 24 linhas em que "Dm" fica longe de "D".

  Mora aqui, e não em cada tela, pelo mesmo motivo de `status_label/1`: os tons
  são vocabulário do domínio, e desde a US 2.3 são dois formulários que os
  desenham — o de vincular (US 2.2) e o da linha do repertório.
  """
  def key_options do
    [
      {"Maiores", Enum.map(@major_keys, &to_string/1)},
      {"Menores", Enum.map(@minor_keys, &to_string/1)}
    ]
  end

  @doc """
  Os três status como opções de `<select>`, rotulados e na ordem em que uma
  música anda: entra em aprendizado, fica pronta, é arquivada.

  **Não há opção em branco**: o status sempre tem um valor, e não se esvazia
  pela tela (US 2.3).
  """
  def status_options, do: Enum.map(@statuses, &{status_label(&1), to_string(&1)})

  @doc """
  Como se escreve o status na tela.

  Mora aqui, e não na LiveView, pela mesma razão de
  `ChurchBands.Bands.BandMember.role_label/1`: é vocabulário do domínio, e a
  US 2.6 e a US 2.3 o mostram em telas diferentes.
  """
  def status_label(:learning), do: "Em aprendizado"
  def status_label(:ready), do: "Pronta"
  def status_label(:archived), do: "Arquivada"

  @doc """
  Changeset do vínculo com o repertório.

  O tom é obrigatório e vem da lista fechada — o `Ecto.Enum` recusa sozinho o
  que não estiver nela, inclusive o que for forçado no formulário.

  A duplicata é recusada pelo índice único do par `(band_id, song_id)`, e não
  por uma consulta antes: a lista de candidatas já esconde as músicas que a
  banda tem, então quem chega aqui com uma repetida forçou o formulário — e é o
  banco que tem a palavra final.
  """
  def changeset(band_repertoire, attrs) do
    band_repertoire
    |> cast(attrs, [:band_id, :song_id, :key, :status])
    |> validate_required([:song_id], message: "escolha a música")
    |> validate_required([:key], message: "escolha o tom")
    |> validate_required([:band_id])
    |> assoc_constraint(:band)
    # `foreign_key_constraint/3` e não `assoc_constraint/3`, pela mesma razão
    # de `BandMember`: o formulário desenha `:song_id`, e é nele que a recusa
    # precisa aparecer.
    |> foreign_key_constraint(:song_id, message: "escolha uma música da lista")
    # A música vem primeiro na lista porque o erro do `unique_constraint/3`
    # cai no primeiro campo, e é `:song_id` que o formulário desenha — no
    # `:band_id` a recusa existiria no changeset sem aparecer na tela. O índice
    # é o mesmo, e `name:` é o que dispensa a ordem de casar com a dele.
    |> unique_constraint([:song_id, :band_id],
      name: :band_repertoires_band_id_song_id_index,
      message: "já está no repertório desta banda"
    )
  end
end
