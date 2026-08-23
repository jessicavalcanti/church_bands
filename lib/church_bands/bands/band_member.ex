defmodule ChurchBands.Bands.BandMember do
  @moduledoc """
  Vínculo de um músico com uma banda (US 1.4).

  O mesmo músico pode ter vários vínculos, um por banda, e cada vínculo carrega
  sua própria função: **instrumentista** (com instrumento) ou **vocalista**
  (com naipe). Guitarrista na Banda Jovem e vocalista na Banda de Domingo são
  dois registros independentes.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band

  @types [:instrumentalist, :vocalist]
  @voice_parts ~w(Soprano Contralto Tenor Baixo)

  schema "band_members" do
    field :type, Ecto.Enum, values: @types
    field :instrument, :string
    field :voice_part, :string

    belongs_to :user, User
    belongs_to :band, Band

    timestamps(type: :utc_datetime)
  end

  @doc """
  Funções aceitas no vínculo.
  """
  def types, do: @types

  @doc """
  Naipes aceitos para vocalistas.
  """
  def voice_parts, do: @voice_parts

  @doc """
  Como se escreve na tela a função deste integrante: o instrumento, para quem
  toca; o naipe, para quem canta.

  Mora aqui, ao lado de `types/0` e `voice_parts/0`, porque é vocabulário do
  domínio e não de uma tela — as três que mostram elenco (o perfil, a banda e a
  lista de pessoas) escreviam cada uma a sua cópia.
  """
  def role_label(%__MODULE__{type: :instrumentalist} = member), do: member.instrument
  def role_label(%__MODULE__{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @doc """
  Changeset do vínculo.

  O campo dependente é decidido pelo tipo: instrumentista exige instrumento e
  vocalista exige naipe. O campo do outro tipo é sempre zerado, para que trocar
  a função no formulário não deixe um instrumento órfão gravado num vocalista.
  """
  def changeset(band_member, attrs) do
    band_member
    |> cast(attrs, [:user_id, :band_id, :type, :instrument, :voice_part])
    |> trim_change(:instrument)
    |> validate_required([:user_id], message: "escolha o músico")
    |> validate_required([:band_id, :type], message: "escolha a função")
    |> validate_length(:instrument, max: 60, message: "precisa ter no máximo 60 caracteres")
    |> validate_inclusion(:voice_part, @voice_parts, message: "escolha um naipe válido")
    |> validate_role_field()
    |> assoc_constraint(:user)
    |> assoc_constraint(:band)
    |> unique_constraint([:user_id, :band_id],
      message: "este músico já é integrante desta banda"
    )
  end

  defp validate_role_field(changeset) do
    case get_field(changeset, :type) do
      :instrumentalist ->
        changeset
        |> put_change(:voice_part, nil)
        |> validate_required([:instrument], message: "informe o instrumento")

      :vocalist ->
        changeset
        |> put_change(:instrument, nil)
        |> validate_required([:voice_part], message: "escolha o naipe")

      nil ->
        changeset
    end
  end
end
