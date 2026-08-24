defmodule ChurchBands.Bands.Instrument do
  @moduledoc """
  Instrumento do grupo de louvor (US 2.8).

  É o catálogo de onde sai a função de todo instrumentista. Existe como tabela,
  e não como lista no código, porque **instrumento muda**: a igreja adquire um
  novo e ele precisa entrar no sistema sem migration. O naipe do vocalista, ao
  lado, continua fixo em `BandMember` pelo motivo oposto — naipe não muda.

  Desativar não é excluir. Um instrumento que saiu de circulação some do
  dropdown de quem monta elenco, mas continua escrito na função de quem o
  tocou; excluir é para o cadastro errado, e só vale enquanto ninguém o toca.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  schema "instruments" do
    field :name, :string
    field :active, :boolean, default: true

    has_many :band_members, ChurchBands.Bands.BandMember

    # Quantos integrantes tocam este instrumento, contado por
    # `Bands.list_instruments/0`. É o que decide se dá para excluir, e o que a
    # mensagem de recusa diz.
    field :member_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de cadastro e renomeação.

  `active` fica **fora** do `cast`: ativar e desativar é operação própria
  (`Bands.set_instrument_active/2`), não um campo que se marca no formulário —
  quem cadastra um instrumento está cadastrando um que existe.
  """
  def changeset(instrument, attrs) do
    instrument
    |> cast(attrs, [:name])
    |> trim_change(:name)
    |> validate_required([:name], message: "informe o nome do instrumento")
    |> validate_length(:name, min: 2, max: 60, message: "precisa ter entre 2 e 60 caracteres")
    # Único sem olhar maiúsculas, como o nome de banda (DT-4). Quem garante é o
    # índice sobre `lower(name)`, então a `unique_constraint` precisa nomeá-lo.
    |> unique_constraint(:name,
      name: :instruments_lower_name_index,
      message: "já existe um instrumento com esse nome"
    )
  end
end
