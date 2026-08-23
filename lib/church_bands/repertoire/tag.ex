defmodule ChurchBands.Repertoire.Tag do
  @moduledoc """
  Tag temática de música (US 2.7).

  É o vocabulário do grupo, não uma lista fechada no código: "Ministração" é
  tag em uma igreja e não é em outra, e a que faltar se cadastra na tela — sem
  deploy, como o instrumento da US 2.8.

  **O nome é único ignorando maiúscula e acento.** "Natal", "natal" e "NATAL"
  são a mesma tag; "Ministração" e "Ministracao" também. Sem isso o catálogo
  acumularia grafias da mesma ideia e o filtro por tag, que chega na US 2.5,
  encontraria metade das músicas.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  alias ChurchBands.Repertoire.Song

  schema "tags" do
    field :name, :string

    many_to_many :songs, Song, join_through: "song_tags"

    # Quantas músicas usam esta tag, contado por `Repertoire.list_tags/0`. É o
    # que decide se dá para excluir, e o que a mensagem de recusa diz.
    field :song_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de cadastro e renomeação.

  Renomear vale para todas as músicas que a usam de uma vez — não existe versão
  antiga do nome. Corrigir a grafia da própria tag não colide consigo mesma,
  porque quem compara é o índice, e a linha comparada é a mesma.
  """
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> trim_change(:name)
    |> validate_required([:name], message: "informe o nome da tag")
    |> validate_length(:name, min: 2, max: 40, message: "precisa ter entre 2 e 40 caracteres")
    # Quem garante a unicidade é o índice sobre `immutable_unaccent(lower(name))`,
    # então a `unique_constraint` precisa nomeá-lo — é o mesmo arranjo do nome
    # de banda (DT-4), com o acento a mais que o catálogo de músicas trouxe.
    |> unique_constraint(:name,
      name: :tags_normalized_name_index,
      message: "já existe uma tag com esse nome"
    )
  end
end
