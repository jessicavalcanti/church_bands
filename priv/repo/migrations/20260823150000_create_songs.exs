defmodule ChurchBands.Repo.Migrations.CreateSongs do
  @moduledoc """
  Catálogo central de músicas (US 2.1), com a busca por título parecido que o
  cadastro usa para avisar sobre duplicata.

  Não existe índice único em `title`: a decisão da história é **avisar, não
  bloquear**. Quem cadastra vê as parecidas e decide se é a mesma música.

  `unaccent` é `STABLE`, e função `STABLE` não entra em índice. O wrapper
  `immutable_unaccent/1` existe por isso — e a US 2.7 o reaproveita para a
  unicidade do nome da tag, então o `down` derruba só o que esta migration
  criou e deixa as extensões de pé.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")

    execute("""
    CREATE OR REPLACE FUNCTION immutable_unaccent(text)
    RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
    $$ SELECT public.unaccent('public.unaccent', $1) $$
    """)

    create table(:songs) do
      add :title, :string, null: false
      add :artist, :string
      add :bpm, :integer
      add :reference_url, :string
      add :chord_chart_url, :string

      timestamps(type: :utc_datetime)
    end

    execute("""
    CREATE INDEX songs_title_trgm_idx
    ON songs USING gin (immutable_unaccent(lower(title)) gin_trgm_ops)
    """)
  end

  def down do
    execute("DROP INDEX songs_title_trgm_idx")

    drop table(:songs)

    execute("DROP FUNCTION immutable_unaccent(text)")
  end
end
