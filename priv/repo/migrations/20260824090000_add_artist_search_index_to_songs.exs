defmodule ChurchBands.Repo.Migrations.AddArtistSearchIndexToSongs do
  @moduledoc """
  A busca do catálogo passa a alcançar o artista (US 2.5), e ganha o índice
  dele.

  O do título veio com a US 2.1, para o aviso de música parecida. Aquele aviso
  compara só o título — o artista é opcional e não serviria de desempate
  confiável. Esta história é a primeira em que alguém procura por
  "Hillsong" esperando achar as músicas da banda, e por isso o índice do
  artista é dela.

  O índice é sobre `immutable_unaccent(lower(artist))`, **sem `coalesce`**: a
  música sem artista simplesmente não é indexada, e a comparação com `NULL` já
  devolve "não casou", que é o que se quer. Envolver a coluna em `coalesce` na
  consulta faria a expressão deixar de casar com a do índice, e o índice não
  seria usado.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX songs_artist_trgm_idx
    ON songs USING gin (immutable_unaccent(lower(artist)) gin_trgm_ops)
    """)
  end

  def down do
    execute("DROP INDEX songs_artist_trgm_idx")
  end
end
