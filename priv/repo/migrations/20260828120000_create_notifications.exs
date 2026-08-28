defmodule ChurchBands.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # A tabela nasce genérica de propósito: a troca é o primeiro emissor, não
      # o único previsto. Por isso não há `swap_request_id` aqui — uma coluna
      # por origem obrigaria uma migration a cada assunto novo que quisesse
      # avisar alguém.
      add :kind, :string, null: false

      # O texto é gravado no momento do fato e nunca se recalcula: a
      # notificação conta o que aconteceu **naquele dia**. Montá-la na leitura
      # exigiria carregar todo o mundo por trás dela — e reescreveria o
      # passado quando o culto mudasse de nome.
      add :title, :string, null: false
      add :body, :text, null: false

      # **Caminho, e não URL.** Guardar `https://…` amarraria a notificação ao
      # endereço de quem a criou; o que se grava é `/swaps`.
      add :path, :string, null: false

      # Nulo é não lida. Notificação não se apaga — marcar como lida basta.
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # A listagem, que é sempre por pessoa e em ordem de chegada.
    create index(:notifications, [:user_id, :inserted_at])

    # O contador do sino roda em **toda** página do portal, e é ele que este
    # índice parcial serve: sem ele a conta varreria o histórico inteiro da
    # pessoa para achar as poucas linhas que ainda não foram lidas.
    create index(:notifications, [:user_id],
             where: "read_at IS NULL",
             name: :notifications_unread_index
           )
  end
end
