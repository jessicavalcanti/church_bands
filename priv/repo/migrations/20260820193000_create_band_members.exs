defmodule ChurchBands.Repo.Migrations.CreateBandMembers do
  use Ecto.Migration

  def change do
    create table(:band_members) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :band_id, references(:bands, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :instrument, :string
      add :voice_part, :string

      timestamps(type: :utc_datetime)
    end

    # Um músico entra uma única vez em cada banda, mas pode estar em várias
    # bandas — por isso o índice é do par, nunca de `user_id` sozinho.
    create unique_index(:band_members, [:user_id, :band_id])
    create index(:band_members, [:band_id])
  end
end
