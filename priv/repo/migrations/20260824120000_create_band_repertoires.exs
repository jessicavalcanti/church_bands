defmodule ChurchBands.Repo.Migrations.CreateBandRepertoires do
  @moduledoc """
  O repertório de cada banda (US 2.2): a linha que liga uma música do catálogo
  a uma banda, no tom em que aquela banda a toca.

  **O tom mora aqui e não em `songs`**, porque ele é da banda: a mesma música
  entra em "D" numa e em "C" na outra. O catálogo não tem tom.
  """
  use Ecto.Migration

  def change do
    create table(:band_repertoires) do
      add :band_id, references(:bands, on_delete: :delete_all), null: false
      # `:restrict` e não `:delete_all`: excluir uma música que alguma banda
      # toca apagaria o repertório dela sem ninguém pedir. Quem recusa de
      # verdade — nomeando as bandas — é `Repertoire.delete_song/1`; isto aqui
      # é a rede embaixo, para o caminho que não passar por lá.
      add :song_id, references(:songs, on_delete: :restrict), null: false
      add :key, :string, null: false
      add :status, :string, null: false, default: "learning"

      timestamps(type: :utc_datetime)
    end

    # Uma música entra uma vez só no repertório de cada banda, mas pode estar
    # em quantas bandas for — por isso o índice é do par, como o de
    # `band_members`. É ele que recusa a duplicata de quem forçar o formulário
    # com uma música que a lista de candidatas já esconde.
    create unique_index(:band_repertoires, [:band_id, :song_id])
    create index(:band_repertoires, [:song_id])
  end
end
