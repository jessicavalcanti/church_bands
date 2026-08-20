defmodule ChurchBands.Bands.Band do
  @moduledoc """
  Banda do grupo de louvor.

  Toda banda tem um Líder de Banda designado (`leader_id`). Esse é o único
  lugar onde o papel "Líder de Banda" existe: ele não é um `global_role`, é
  derivado deste relacionamento.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Accounts.User

  schema "bands" do
    field :name, :string
    field :description, :string

    belongs_to :leader, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de criação e edição de banda.

  `leader_id` vem do formulário de propósito — escolher o líder é a decisão
  central desta tela. Quem pode usar o formulário é decidido antes, na
  autorização; o changeset só garante que o líder escolhido existe.
  """
  def changeset(band, attrs) do
    band
    |> cast(attrs, [:name, :description, :leader_id])
    |> update_change(:name, &trim/1)
    |> validate_required([:name], message: "informe o nome da banda")
    |> validate_required([:leader_id], message: "escolha o Líder de Banda")
    |> validate_length(:name,
      min: 2,
      max: 120,
      message: "precisa ter entre 2 e 120 caracteres"
    )
    |> validate_length(:description, max: 500, message: "precisa ter no máximo 500 caracteres")
    |> assoc_constraint(:leader)
  end

  # `cast/3` transforma string vazia em `nil`, então o trim precisa aceitá-lo.
  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)
end
