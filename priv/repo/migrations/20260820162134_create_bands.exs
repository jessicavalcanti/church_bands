defmodule ChurchBands.Repo.Migrations.CreateBands do
  use Ecto.Migration

  def change do
    create table(:bands) do
      add :name, :string, null: false
      add :description, :text
      add :leader_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:bands, [:leader_id])
  end
end
