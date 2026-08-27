defmodule ChurchBands.Repo.Migrations.CreateSwapRequests do
  use Ecto.Migration

  def change do
    create table(:swap_requests) do
      add :requester_event_band_id, references(:event_bands, on_delete: :delete_all), null: false
      add :requester_member_id, references(:band_members, on_delete: :delete_all), null: false
      add :target_event_band_id, references(:event_bands, on_delete: :delete_all), null: false
      add :target_member_id, references(:band_members, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    # O pedido é de **vaga para vaga**: as duas escalas e os dois vínculos, e
    # nunca `user_id`. Quem é a pessoa se lê do vínculo; qual o evento, da
    # escala. É o que faz o `on_delete: :delete_all` das quatro chaves valer
    # como regra de negócio — desescalar a banda ou tirar a pessoa dela apaga o
    # pedido, sem nenhuma limpeza escrita à mão. Um pedido que sobrevivesse à
    # vaga que o originou apontaria para uma escala que não existe mais.
    create unique_index(:swap_requests, [:requester_event_band_id, :requester_member_id],
             where: "status = 'pending'",
             name: :swap_requests_one_pending_per_slot_index
           )

    # A lista de recebidos de `/swaps`.
    create index(:swap_requests, [:target_member_id])

    # O elenco do evento, que na US 4.3 precisa saber quais vagas dali estão
    # trocadas.
    create index(:swap_requests, [:target_event_band_id])
  end
end
