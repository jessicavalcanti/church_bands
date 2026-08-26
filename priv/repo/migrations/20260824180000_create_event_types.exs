defmodule ChurchBands.Repo.Migrations.CreateEventTypes do
  @moduledoc """
  Tipos de evento do calendário (US 3.1) — a primeira tabela da Fase 3.

  **Tipo de evento é dado, e não código.** Um enum `culto | ensaio |
  confraternizacao` obrigaria uma migration toda vez que a igreja inventasse
  uma "Vigília" ou um "Batismo", e ela inventa com frequência maior do que a de
  um deploy. Vira tabela com tela de gerenciamento, como as tags da US 2.7 e os
  instrumentos da US 2.8.

  `band_leader_can_create` é a consequência disso: com o tipo virando dado, a
  pergunta "o Líder de Banda pode marcar isto?" não pode morar num `case` sobre
  nomes no código — o tipo cadastrado depois nasceria sem resposta. Cada tipo
  carrega a sua. Aqui a marcação só se grava e se exibe; quem a lê é a criação
  de evento pelo Líder de Banda, que depende da escala e por isso mora na
  US 3.4 — o mesmo desenho de `band_repertoires.status`, que nasceu na US 2.2 e
  só ganhou tela na 2.3.

  A unicidade do nome reaproveita o `immutable_unaccent/1` que a US 2.1 criou
  junto das extensões `pg_trgm` e `unaccent`: "Vigília", "vigilia" e "VIGÍLIA"
  são o mesmo tipo, como "Confraternização" e "Confraternizacao". Por isso o
  `down` derruba só a tabela e deixa a função de pé — ela é do catálogo de
  músicas, e as tags também dependem dela.
  """
  use Ecto.Migration

  # Os três com que o calendário nasce. Daqui em diante são cadastro como
  # qualquer outro: quem tem acesso total renomeia, acrescenta e exclui. Só o
  # ensaio nasce marcado — é o único que o Líder de Banda marca sozinho, para a
  # própria banda. O banco de teste também nasce com os três.
  @initial [
    {"Culto", false},
    {"Ensaio", true},
    {"Confraternização", false}
  ]

  def up do
    create table(:event_types) do
      add :name, :string, null: false
      add :band_leader_can_create, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    execute(
      "CREATE UNIQUE INDEX event_types_normalized_name_index ON event_types (immutable_unaccent(lower(name)))"
    )

    values =
      Enum.map_join(@initial, ", ", fn {name, can_create} ->
        "('#{name}', #{can_create}, now() at time zone 'utc', now() at time zone 'utc')"
      end)

    execute("""
    INSERT INTO event_types (name, band_leader_can_create, inserted_at, updated_at)
    VALUES #{values}
    """)
  end

  def down do
    drop table(:event_types)
  end
end
