defmodule ChurchBands.Changesets do
  @moduledoc """
  Peças de changeset que valem para mais de um schema.

  Aqui entra só o que os três schemas fariam igual — e não a validação que é de
  um schema só, que continua morando ao lado do campo que ela protege.
  """
  alias Ecto.Changeset

  @doc """
  Tira os espaços das pontas de `field`, quando ele veio no changeset.

  `cast/3` transforma em `nil` tudo que é só espaço, então o trim precisa
  aceitar `nil`: campo opcional deixado em branco fica `nil`, e não uma string
  vazia gravada no banco.
  """
  def trim_change(%Changeset{} = changeset, field) do
    Changeset.update_change(changeset, field, &trim/1)
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)
end
