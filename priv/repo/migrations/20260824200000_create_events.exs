defmodule ChurchBands.Repo.Migrations.CreateEvents do
  @moduledoc """
  Os eventos da agenda da igreja (US 3.2) — a tabela que dá conteúdo ao
  calendário cujo vocabulário nasceu na US 3.1.

  **O evento é um ponto no tempo, e não um intervalo.** Não há hora de término
  porque a igreja não tem essa informação — o culto acaba quando acaba. Sem ela
  a "sobreposição" da escala (US 3.4) vira uma janela fixa a partir do início,
  que é mais simples de explicar e de testar do que interseção de intervalos
  que ninguém sabe medir.

  `starts_at` é `:utc_datetime` como todo instante do sistema. A hora de parede
  aparece só na borda (`ChurchBandsWeb.LocalTime`): guardar o deslocamento
  junto faria todo culto do calendário andar uma hora no dia em que o horário
  de verão voltar a existir.

  **`on_delete: :nothing` no tipo é regra, não descuido.** É ele que sustenta
  no banco a trava que a US 3.1 deixou para cá: tipo com evento não se exclui.
  Quem produz a mensagem com a contagem é `Schedule.delete_event_type/1`, que
  conta antes de tentar — o erro do banco é a rede embaixo, não o caminho.

  `status` é texto com `Ecto.Enum` em cima, como `band_repertoires.status`
  (US 2.2). Cancelar **preserva**: o culto cancelado continua no calendário,
  riscado, senão quem não olhar de novo é surpreendido no domingo.
  """
  use Ecto.Migration

  def change do
    create table(:events) do
      add :event_type_id, references(:event_types, on_delete: :nothing), null: false
      add :title, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :location, :string
      add :notes, :text
      add :status, :string, null: false, default: "scheduled"

      timestamps(type: :utc_datetime)
    end

    # A lista e a grade leem sempre faixa de datas, nunca a tabela inteira.
    create index(:events, [:starts_at])

    # Serve a três leituras: a trava de tipo em uso, a contagem por tipo em
    # `/event-types` e o filtro por tipo que chega na US 3.3.
    create index(:events, [:event_type_id])
  end
end
