defmodule ChurchBands.Repo.Migrations.CreatePasswordResetTokens do
  use Ecto.Migration

  def change do
    create table(:password_reset_tokens) do
      # Guardamos o hash do token, não o token. Quem ler o banco não consegue
      # redefinir a senha de ninguém — o valor que abre o link só existe no
      # e-mail enviado.
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:password_reset_tokens, [:token_hash])
    create index(:password_reset_tokens, [:user_id])
  end
end
