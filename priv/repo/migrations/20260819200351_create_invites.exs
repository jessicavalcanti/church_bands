defmodule ChurchBands.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  def change do
    create table(:invites) do
      add :email, :citext, null: false
      add :token, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :invited_by_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:token])
    create index(:invites, [:invited_by_id])

    # Um mesmo e-mail pode ter vários convites ao longo do tempo (cancelado,
    # expirado, reenviado), mas nunca dois pendentes ao mesmo tempo.
    create unique_index(:invites, [:email],
             where: "status = 'pending'",
             name: :invites_email_pending_index
           )
  end
end
