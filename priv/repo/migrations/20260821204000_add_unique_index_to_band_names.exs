defmodule ChurchBands.Repo.Migrations.AddUniqueIndexToBandNames do
  @moduledoc """
  Nome de banda passa a ser único (DT-4).

  O índice é sobre `lower(name)`, não sobre `name`: duas bandas chamadas
  "Banda Jovem" e "banda jovem" são a mesma banda para quem lê uma lista, e
  deixar as duas existirem manteria exatamente a confusão que o débito
  descreve — escolher a banda errada na escala ou no repertório.

  O nome já chega aparado pelo changeset, então espaço na ponta não é uma
  terceira grafia.

  Se o banco já tiver duas bandas com o mesmo nome, a migration falha ao criar
  o índice — o conserto é renomear uma delas antes de subir.
  """
  use Ecto.Migration

  def up do
    execute("CREATE UNIQUE INDEX bands_lower_name_index ON bands (lower(name))")
  end

  def down do
    execute("DROP INDEX bands_lower_name_index")
  end
end
