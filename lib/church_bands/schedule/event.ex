defmodule ChurchBands.Schedule.Event do
  @moduledoc """
  Um evento da agenda da igreja (US 3.2).

  É o culto, o ensaio, a vigília — o que a igreja marca. O **tipo** vem do
  vocabulário da US 3.1 e é obrigatório: sem ele o calendário vira lista de
  títulos soltos, e o filtro da US 3.3 não teria por onde pegar.

  **Título não é único de propósito.** Dois cultos podem se chamar "Culto da
  Noite" — e vão se chamar, toda semana. Quem distingue um do outro é a data.

  **`starts_at_local` é o campo que o formulário vê.** O `starts_at` do banco é
  UTC, e ligar o `datetime-local` direto nele mostraria a hora do servidor e
  deslocaria o horário a cada `phx-change`. O virtual recebe a hora de parede,
  o changeset converte uma vez e grava o instante — e o erro de data cai **no
  campo que a pessoa está olhando**, e não num flash.

  **`status` não entra em changeset nenhum.** Quem o muda são
  `Schedule.cancel_event/1` e `Schedule.reopen_event/1`, por `change/2`. É o
  que impede um parâmetro forjado no formulário de cancelar um evento pela
  porta dos fundos — o mesmo cuidado do `active` do instrumento (US 2.8).
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule.EventType

  schema "events" do
    field :title, :string
    field :starts_at, :utc_datetime
    field :location, :string
    field :notes, :string
    field :status, Ecto.Enum, values: [:scheduled, :cancelled], default: :scheduled

    # A hora de parede que o formulário lê e escreve. Nunca chega ao banco: o
    # `changeset/2` a converte em `starts_at` e ela morre aqui.
    field :starts_at_local, :naive_datetime, virtual: true

    belongs_to :event_type, EventType

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de edição — e a base do de criação.

  Editar um evento que já passou é permitido, inclusive salvando de novo a data
  antiga: a recusa de data no passado é só da criação, e por isso mora em
  `creation_changeset/2`. Travar a edição impediria corrigir o título de um
  culto de semana passada, que é justamente quando se descobre o erro.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type_id, :title, :starts_at_local, :location, :notes])
    |> trim_change(:title)
    |> trim_change(:location)
    |> put_starts_at()
    |> validate_required([:event_type_id], message: "escolha o tipo do evento")
    |> validate_required([:title], message: "informe o título do evento")
    |> validate_starts_at()
    |> validate_length(:title, min: 2, max: 80, message: "precisa ter entre 2 e 80 caracteres")
    |> validate_length(:location, max: 120, message: "precisa ter no máximo 120 caracteres")
    # `foreign_key_constraint` no `event_type_id`, e não `assoc_constraint` na
    # associação: o `assoc_constraint` pendura o erro em `:event_type`, e o
    # campo que o formulário desenha é o `_id` — a mensagem existiria no
    # changeset e não apareceria na tela, como a da data.
    |> foreign_key_constraint(:event_type_id,
      message: "escolha um tipo de evento que exista"
    )
  end

  @doc """
  Changeset de criação: o de edição mais a recusa de marcar no passado.

  É changeset separado, e não uma opção do mesmo, porque essa é a **única**
  regra que diferencia criar de editar — passá-la por opção plantaria no
  caminho da edição um `if` que ela sempre teria de furar.

  A fronteira é o **instante**, e não o dia: um evento para daqui a uma hora é
  válido, e um para uma hora atrás não é. É o que impede o erro de digitar o
  ano errado sem atrapalhar quem marca um culto para hoje à noite.
  """
  def creation_changeset(event, attrs) do
    event
    |> changeset(attrs)
    |> validate_not_in_the_past()
  end

  # A conversão acontece uma vez só, e só quando a hora de parede mudou: o
  # `starts_at` gravado não se reconverte a cada `phx-change`, senão o horário
  # andaria sozinho a cada tecla digitada em outro campo.
  defp put_starts_at(changeset) do
    case fetch_change(changeset, :starts_at_local) do
      {:ok, naive} -> put_change(changeset, :starts_at, LocalTime.from_local(naive))
      :error -> changeset
    end
  end

  # `validate_required(:starts_at)` penduraria a mensagem num campo que a tela
  # não desenha, e ela não apareceria para ninguém; `validate_required` no
  # virtual quebraria o `update_event/2` que muda só o título, porque o virtual
  # não vem do banco. Olhar o `starts_at` **resultante** resolve os dois: no
  # evento novo ele é nulo e a recusa aparece no campo certo; no que já existe
  # ele já está lá, e não se exige redigitar a data para corrigir o título.
  defp validate_starts_at(changeset) do
    if get_field(changeset, :starts_at) do
      changeset
    else
      add_error(changeset, :starts_at_local, "informe a data e a hora do evento")
    end
  end

  # O erro cai em `starts_at_local`, e não em `starts_at`: é o virtual que tem
  # campo na tela, e mensagem pendurada num campo que não se desenha não
  # aparece para ninguém.
  defp validate_not_in_the_past(changeset) do
    case get_change(changeset, :starts_at) do
      nil ->
        changeset

      starts_at ->
        if DateTime.before?(starts_at, LocalTime.now()) do
          add_error(changeset, :starts_at_local, "não dá para marcar um evento no passado")
        else
          changeset
        end
    end
  end
end
