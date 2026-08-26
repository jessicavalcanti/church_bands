defmodule ChurchBands.Schedule.EventType do
  @moduledoc """
  Tipo de evento do calendário (US 3.1).

  É o vocabulário da igreja para o que ela marca na agenda: "Culto", "Ensaio",
  "Vigília", "Batismo". Existe como tabela, e não como enum no código, porque
  **a igreja inventa tipo de evento mais rápido do que se faz um deploy** — o
  mesmo motivo da tag da US 2.7 e do instrumento da US 2.8.

  **O nome é único ignorando maiúscula e acento.** "Vigília", "vigilia" e
  "VIGÍLIA" são o mesmo tipo; "Confraternização" e "Confraternizacao" também.
  Sem isso o calendário acumularia grafias da mesma ideia, e filtrar por tipo
  encontraria metade dos eventos.

  `band_leader_can_create` responde, por tipo, se o Líder de Banda pode marcar
  um evento daquele tipo. Ela é **do tipo e não do evento**: quem a lê é a
  criação de evento (US 3.4), na hora, e não uma cópia dentro do evento já
  criado — desmarcar "Ensaio" amanhã não desfaz o ensaio marcado ontem.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  alias ChurchBands.Schedule.Event

  schema "event_types" do
    field :name, :string
    field :band_leader_can_create, :boolean, default: false

    has_many :events, Event

    # Quantos eventos usam este tipo, contado por `Schedule.list_event_types/0`
    # (US 3.2). É o que a lista mostra e o que decide se dá para excluir — o
    # mesmo arranjo do `song_count` da tag.
    field :event_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de cadastro e renomeação.

  Diferente do `active` do instrumento, a marcação entra no `cast`: ela **é**
  um campo do formulário, e não uma operação à parte — quem cadastra um tipo
  de evento já sabe se o líder pode marcá-lo.

  Corrigir a grafia do próprio tipo não colide consigo mesmo, porque quem
  compara é o índice, e a linha comparada é a mesma.
  """
  def changeset(event_type, attrs) do
    event_type
    |> cast(attrs, [:name, :band_leader_can_create])
    |> trim_change(:name)
    |> validate_required([:name], message: "informe o nome do tipo de evento")
    |> validate_length(:name, min: 2, max: 40, message: "precisa ter entre 2 e 40 caracteres")
    # Quem garante a unicidade é o índice sobre `immutable_unaccent(lower(name))`,
    # então a `unique_constraint` precisa nomeá-lo — o mesmo arranjo da tag
    # (US 2.7), que é o do nome de banda (DT-4) com o acento a mais.
    |> unique_constraint(:name,
      name: :event_types_normalized_name_index,
      message: "já existe um tipo de evento com esse nome"
    )
  end
end
