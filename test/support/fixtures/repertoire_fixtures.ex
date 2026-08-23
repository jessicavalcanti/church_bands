defmodule ChurchBands.RepertoireFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Repertoire`.
  """

  alias ChurchBands.Repertoire

  @doc """
  Cadastra uma música no catálogo. Só o título tem valor padrão, porque só ele
  é obrigatório — o resto entra quando o teste tiver algo a dizer sobre ele.

  `tags:` recebe as tags já cadastradas com que a música nasce marcada, e vira
  a lista de ids que o contexto espera — o teste fala de tags, não de ids.
  """
  def song_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{title: "Música #{System.unique_integer([:positive])}"})
      |> take_tags()

    {:ok, song} = Repertoire.create_song(attrs)
    song
  end

  defp take_tags(%{tags: tags} = attrs) do
    attrs
    |> Map.delete(:tags)
    |> Map.put(:tag_ids, Enum.map(tags, & &1.id))
  end

  defp take_tags(attrs), do: attrs

  @doc """
  Cadastra uma tag temática.

  O nome padrão é único porque o banco de teste **já nasce com as sete tags
  iniciais** da migration: o teste que precisa de uma tag nova precisa de um
  nome que nenhuma delas tenha.
  """
  def tag_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{name: "Tag #{System.unique_integer([:positive])}"})

    {:ok, tag} = Repertoire.create_tag(attrs)
    tag
  end
end
