defmodule ChurchBands.Bands.BandMember do
  @moduledoc """
  Vínculo de um músico com uma banda (US 1.4).

  O mesmo músico pode ter vários vínculos, um por banda, e cada vínculo carrega
  sua própria função: **instrumentista** (com instrumento) ou **vocalista**
  (com naipe). Guitarrista na Banda Jovem e vocalista na Banda de Domingo são
  dois registros independentes.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.Instrument

  @types [:instrumentalist, :vocalist]
  @voice_parts ~w(Soprano Contralto Tenor Baixo)

  schema "band_members" do
    field :type, Ecto.Enum, values: @types
    field :voice_part, :string

    belongs_to :user, User
    belongs_to :band, Band
    belongs_to :instrument, Instrument

    timestamps(type: :utc_datetime)
  end

  @doc """
  Funções aceitas no vínculo.
  """
  def types, do: @types

  @doc """
  Naipes aceitos para vocalistas.

  Continua sendo lista no código, e não tabela como os instrumentos (US 2.8):
  naipe é vocabulário fechado da música coral, não patrimônio que a igreja
  adquire.
  """
  def voice_parts, do: @voice_parts

  @doc """
  Como se escreve na tela a função deste integrante: o instrumento, para quem
  toca; o naipe, para quem canta.

  Mora aqui, ao lado de `types/0` e `voice_parts/0`, porque é vocabulário do
  domínio e não de uma tela — as três que mostram elenco (o perfil, a banda e a
  lista de pessoas) escreviam cada uma a sua cópia.
  """
  def role_label(%__MODULE__{type: :instrumentalist} = member), do: member.instrument.name
  def role_label(%__MODULE__{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @doc """
  Changeset do vínculo.

  O campo dependente é decidido pelo tipo: instrumentista exige instrumento e
  vocalista exige naipe. O campo do outro tipo é sempre zerado, para que trocar
  a função no formulário não deixe um instrumento órfão gravado num vocalista.

  Desde a US 2.8 o instrumento é um id do catálogo, não um nome digitado: o
  dropdown da tela é conveniência, e quem garante que o instrumento existe é a
  `assoc_constraint/3` aqui embaixo — forçar o evento com um id inventado é
  recusado igual.
  """
  def changeset(band_member, attrs) do
    band_member
    |> cast(attrs, [:user_id, :band_id, :type, :instrument_id, :voice_part])
    |> validate_required([:user_id], message: "escolha o músico")
    |> validate_required([:band_id, :type], message: "escolha a função")
    |> validate_inclusion(:voice_part, @voice_parts, message: "escolha um naipe válido")
    |> validate_role_field()
    |> assoc_constraint(:user)
    |> assoc_constraint(:band)
    # `foreign_key_constraint/3` e não `assoc_constraint/3`: a segunda põe o erro
    # no campo `:instrument`, e quem o formulário desenha é `:instrument_id` —
    # a recusa existiria no changeset e não apareceria na tela.
    |> foreign_key_constraint(:instrument_id, message: "escolha um instrumento da lista")
    |> unique_constraint([:user_id, :band_id],
      message: "este músico já é integrante desta banda"
    )
  end

  defp validate_role_field(changeset) do
    case get_field(changeset, :type) do
      :instrumentalist ->
        changeset
        |> put_change(:voice_part, nil)
        |> validate_required([:instrument_id], message: "informe o instrumento")

      :vocalist ->
        changeset
        |> put_change(:instrument_id, nil)
        |> validate_required([:voice_part], message: "escolha o naipe")

      nil ->
        changeset
    end
  end
end
