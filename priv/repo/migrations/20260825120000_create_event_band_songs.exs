defmodule ChurchBands.Repo.Migrations.CreateEventBandSongs do
  @moduledoc """
  O set de cada banda escalada num evento (US 3.6): a sequência de músicas que
  aquela banda toca naquele culto, na ordem e no tom em que toca.

  **Pendura-se na escala, e não no evento**, porque duas bandas no mesmo culto
  tocam coisas diferentes — o set é do par evento × banda, que é exatamente o
  que `event_bands` já é. Por isso `on_delete: :delete_all` ali: desescalar a
  banda leva junto o set dela, que sem a escala não teria dono.

  **A música aponta para o catálogo, e não para o repertório da banda.** É o
  que preserva o histórico: o set de um culto passado continua dizendo o que
  foi tocado mesmo que a banda largue a música depois. A alternativa — apontar
  para `band_repertoires` com cascata — faria sair do repertório reescrever o
  passado. O `on_delete: :nothing` é a rede embaixo disso; quem recusa de
  verdade é `Repertoire.delete_song/1`, que já nomeia as bandas.

  **Sem índice único em `(event_band_id, song_id)`**, e isso é regra e não
  descuido: há quem abra e encerre o culto com a mesma canção, então a mesma
  música entra duas vezes no mesmo set, em posições diferentes.
  """
  use Ecto.Migration

  def change do
    create table(:event_band_songs) do
      add :event_band_id, references(:event_bands, on_delete: :delete_all), null: false
      add :song_id, references(:songs, on_delete: :nothing), null: false
      add :position, :integer, null: false
      # Nulo é o padrão e quer dizer "o tom da banda": o tom herda do
      # repertório, e a coluna só grava a exceção daquele culto. Uma fonte da
      # verdade com exceção explícita, em vez de duas cópias para divergirem.
      add :key, :string

      timestamps(type: :utc_datetime)
    end

    # A leitura do set é sempre "as músicas desta escala, na ordem" — é este o
    # par que ela percorre.
    create index(:event_band_songs, [:event_band_id, :position])

    # Serve à trava de remoção do repertório, que pergunta pela música e não
    # pela escala: "esta música está no set de algum evento futuro?".
    create index(:event_band_songs, [:song_id])
  end
end
