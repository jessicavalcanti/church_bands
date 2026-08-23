defmodule ChurchBands.RepertoireFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Repertoire`.
  """

  alias ChurchBands.Repertoire

  @doc """
  Cadastra uma música no catálogo. Só o título tem valor padrão, porque só ele
  é obrigatório — o resto entra quando o teste tiver algo a dizer sobre ele.
  """
  def song_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{title: "Música #{System.unique_integer([:positive])}"})

    {:ok, song} = Repertoire.create_song(attrs)
    song
  end
end
