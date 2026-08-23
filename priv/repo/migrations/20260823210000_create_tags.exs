defmodule ChurchBands.Repo.Migrations.CreateTags do
  @moduledoc """
  Tags temáticas das músicas (US 2.7).

  O catálogo da US 2.1 nasceu sem elas de propósito — marcar exige uma tela de
  cadastro, e ela é esta. Daqui em diante a música carrega o vocabulário do
  grupo: em que momento do culto ela entra, de que época ela é.

  **`song_tags` não leva timestamps.** É o que permite mapear a associação com
  `join_through: "song_tags"` puro e `put_assoc/4`: com `inserted_at` not null,
  o Ecto não teria como preenchê-lo sem um schema de junção só para isso — e a
  data em que alguém marcou uma tag não é informação que ninguém consulta.

  A unicidade do nome reaproveita o `immutable_unaccent/1` que a US 2.1 criou:
  "Ministração" e "Ministracao" são a mesma tag, como "Natal" e "natal". Por
  isso o `down` derruba só as tabelas e o índice, e deixa a função de pé.
  """
  use Ecto.Migration

  # As sete com que o sistema nasce — o vocabulário mínimo de um culto. Daqui
  # em diante são cadastro como qualquer outro: quem cura o catálogo renomeia,
  # acrescenta e exclui. O banco de teste também nasce com elas.
  @initial ["Louvor", "Adoração", "Celebração", "Natal", "Páscoa", "Santa Ceia", "Oferta"]

  def up do
    create table(:tags) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    execute(
      "CREATE UNIQUE INDEX tags_normalized_name_index ON tags (immutable_unaccent(lower(name)))"
    )

    # Sem chave primária: quem identifica a linha é o par, e o índice único
    # abaixo é quem garante que ele não se repita. Marcar duas vezes a mesma
    # tag na mesma música é a mesma marcação.
    create table(:song_tags, primary_key: false) do
      add :song_id, references(:songs, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :nothing), null: false
    end

    create unique_index(:song_tags, [:song_id, :tag_id])
    create index(:song_tags, [:tag_id])

    values =
      Enum.map_join(@initial, ", ", fn name ->
        "('#{name}', now() at time zone 'utc', now() at time zone 'utc')"
      end)

    execute("INSERT INTO tags (name, inserted_at, updated_at) VALUES #{values}")
  end

  def down do
    drop table(:song_tags)

    execute("DROP INDEX tags_normalized_name_index")

    drop table(:tags)
  end
end
