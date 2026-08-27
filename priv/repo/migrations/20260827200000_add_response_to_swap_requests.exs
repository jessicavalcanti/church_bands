defmodule ChurchBands.Repo.Migrations.AddResponseToSwapRequests do
  use Ecto.Migration

  def change do
    alter table(:swap_requests) do
      # `mode` só existe em pedido aceito: é a diferença entre *cobrir* — o
      # alvo assume o dia de quem pediu e mantém o seu — e *trocar o dia*, em
      # que as duas vagas mudam de dono. Pendente, cancelado e recusado não
      # têm modo, e por isso a coluna nasce nula.
      add :mode, :string
      add :responded_at, :utc_datetime
    end

    # É por este índice que o elenco de um evento descobre quais vagas dali
    # estão trocadas. Ele é **parcial** porque é só o aceito que a tela lê: o
    # pendente já tem o índice único da US 4.2, e cancelado e recusado não
    # incidem em escala nenhuma.
    #
    # O par dele do outro lado já existe desde a US 4.2
    # (`swap_requests_target_event_band_id_index`), e é o que responde pela
    # ponta do alvo no modo *trocar o dia*.
    create index(:swap_requests, [:requester_event_band_id],
             where: "status = 'accepted'",
             name: :swap_requests_accepted_origin_index
           )
  end
end
