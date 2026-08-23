defmodule ChurchBands.Bands.Band do
  @moduledoc """
  Banda do grupo de louvor.

  Toda banda tem um Líder de Banda designado (`leader_id`). Esse é o único
  lugar onde o papel "Líder de Banda" existe: ele não é um `global_role`, é
  derivado deste relacionamento.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  alias ChurchBands.Accounts.User

  schema "bands" do
    field :name, :string
    field :description, :string

    belongs_to :leader, User
    has_many :band_members, ChurchBands.Bands.BandMember

    # Tamanho do elenco, contado por `Bands.list_bands/0` para a lista de
    # bandas (US 1.6). Segue a regra de `list_roster/1` — o Líder de Banda
    # conta mesmo sem vínculo —, e por isso não é `length(band_members)`.
    field :roster_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de criação e edição de banda.

  `leader_id` vem do formulário de propósito — escolher o líder é a decisão
  central desta tela. Quem pode usar o formulário é decidido antes, na
  autorização; o changeset só garante que o líder escolhido existe.

  O nome é único no grupo, sem distinguir maiúsculas (DT-4): da Fase 3 em
  diante a banda vira item de escala e de calendário, e duas com o mesmo nome
  numa lista de escolha são erro esperando acontecer.
  """
  def changeset(band, attrs) do
    band
    |> cast(attrs, [:name, :description, :leader_id])
    |> trim_change(:name)
    |> validate_required([:name], message: "informe o nome da banda")
    |> validate_required([:leader_id], message: "escolha o Líder de Banda")
    |> validate_length(:name,
      min: 2,
      max: 120,
      message: "precisa ter entre 2 e 120 caracteres"
    )
    |> validate_length(:description, max: 500, message: "precisa ter no máximo 500 caracteres")
    |> assoc_constraint(:leader)
    # O nome é único sem olhar maiúsculas (DT-4): "Banda Jovem" e "banda jovem"
    # são a mesma banda para quem escolhe numa lista. Quem garante é o índice
    # sobre `lower(name)`, então a `unique_constraint` precisa nomeá-lo.
    |> unique_constraint(:name,
      name: :bands_lower_name_index,
      message: "já existe uma banda com esse nome"
    )
  end
end
