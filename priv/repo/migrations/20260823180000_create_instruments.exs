defmodule ChurchBands.Repo.Migrations.CreateInstruments do
  @moduledoc """
  O instrumento do integrante deixa de ser texto livre e vira cadastro (US 2.8).

  A US 1.4 gravava o nome digitado direto no vínculo, com um `<datalist>` de
  sugestões que não obrigava nada — "Bateria", "Baterista" e "Batera" eram três
  instrumentos diferentes para o sistema. Aqui o instrumento passa a ser uma
  linha de `instruments`, e o vínculo passa a apontar para ela.

  A migration **move dados**, e não só estrutura, por isso `up` e `down` são
  escritos à mão. O que já estava gravado **não se perde**: cada grafia
  distinta que existe em `band_members` vira um cadastro, inclusive as fora de
  padrão. Padronizar o que sobrou é trabalho de quem cura o catálogo, na tela
  nova — renomear o certo, reatribuir os integrantes do errado, excluir o que
  ficou sem ninguém.
  """
  use Ecto.Migration

  # Os mesmos onze que a US 1.4 oferecia como sugestão. Daqui em diante são
  # cadastro como qualquer outro: podem ser renomeados, desativados ou
  # excluídos.
  @initial ~w(Violão Guitarra Baixo Bateria Teclado Piano Percussão Saxofone Trompete Violino Flauta)

  def up do
    create table(:instruments) do
      add :name, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    # Único sem distinguir maiúsculas, no mesmo formato de
    # `bands_lower_name_index` (DT-4): "Bateria" e "bateria" são o mesmo
    # instrumento para quem escolhe numa lista.
    execute("CREATE UNIQUE INDEX instruments_lower_name_index ON instruments (lower(name))")

    values =
      Enum.map_join(@initial, ", ", fn name ->
        "('#{name}', true, now() at time zone 'utc', now() at time zone 'utc')"
      end)

    execute("INSERT INTO instruments (name, active, inserted_at, updated_at) VALUES #{values}")

    # O que já estava escrito nos vínculos e ainda não está no catálogo entra
    # agora. `DISTINCT ON (lower(btrim(...)))` colapsa as diferenças de caixa e
    # de espaço, que o índice recusaria, e guarda a primeira grafia em ordem.
    execute("""
    INSERT INTO instruments (name, active, inserted_at, updated_at)
    SELECT DISTINCT ON (lower(btrim(instrument)))
           btrim(instrument), true, now() at time zone 'utc', now() at time zone 'utc'
      FROM band_members
     WHERE instrument IS NOT NULL
       AND btrim(instrument) <> ''
       AND lower(btrim(instrument)) NOT IN (SELECT lower(name) FROM instruments)
     ORDER BY lower(btrim(instrument))
    """)

    # Nulo permitido: vocalista não tem instrumento. `on_delete: :nothing`
    # é deliberado — a trava de exclusão mora no contexto, com a contagem que
    # produz a mensagem de recusa.
    alter table(:band_members) do
      add :instrument_id, references(:instruments, on_delete: :nothing)
    end

    create index(:band_members, [:instrument_id])

    execute("""
    UPDATE band_members m
       SET instrument_id = i.id
      FROM instruments i
     WHERE m.instrument IS NOT NULL
       AND lower(btrim(m.instrument)) = lower(i.name)
    """)

    alter table(:band_members) do
      remove :instrument
    end
  end

  def down do
    alter table(:band_members) do
      add :instrument, :string
    end

    execute("""
    UPDATE band_members m
       SET instrument = i.name
      FROM instruments i
     WHERE m.instrument_id = i.id
    """)

    alter table(:band_members) do
      remove :instrument_id
    end

    drop table(:instruments)
  end
end
