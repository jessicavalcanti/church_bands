defmodule ChurchBands.Repo.Migrations.CreateEventBands do
  @moduledoc """
  A escala de bandas de cada evento (US 3.4) — a linha que responde "quem toca
  neste culto".

  **É tabela própria, e não um `band_id` no evento**, porque a escala é de 0 a
  N: confraternização pode não ter banda nenhuma, e culto grande pode ter duas.
  Um campo no evento resolveria o caso comum e travaria os outros dois — e é
  nesta linha (evento × banda) que o set da US 3.6 se pendura, com as músicas
  que aquela banda toca naquele evento.

  **`on_delete: :nothing` nas duas pontas é regra escrita no banco.** No evento
  ela sustenta a trava que a US 3.2 deixou para cá: evento com banda escalada
  não se exclui, cancela-se. Na banda ela impede que apagar uma banda esvazie a
  escala de cultos que já aconteceram.

  **A janela de conflito de 3 horas não está aqui.** Ela compara o `starts_at`
  de eventos *diferentes*, e isso nenhuma constraint de tabela sabe fazer —
  mora em `ChurchBands.Schedule`, como constante nomeada.
  """
  use Ecto.Migration

  def change do
    create table(:event_bands) do
      add :event_id, references(:events, on_delete: :nothing), null: false
      add :band_id, references(:bands, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    # A mesma banda não entra duas vezes no mesmo evento. A lista de candidatas
    # já esconde as que estão escaladas; o índice é o que responde a quem
    # forçar o formulário.
    create unique_index(:event_bands, [:event_id, :band_id])

    # Serve a três leituras que perguntam pela banda, e não pelo evento: o
    # filtro do calendário, a janela de conflito e o bloco de próximos eventos
    # do portal (US 3.5).
    create index(:event_bands, [:band_id])
  end
end
