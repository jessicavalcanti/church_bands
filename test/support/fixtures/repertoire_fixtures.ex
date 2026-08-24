defmodule ChurchBands.RepertoireFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Repertoire`.
  """

  import ChurchBands.BandsFixtures

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

  @doc """
  Põe uma música no repertório de uma banda (US 2.2). Aceita `:band` e `:song`
  para reaproveitar registros existentes; do contrário cria os dois.

  O tom padrão é "C" porque o teste que não fala de tom não está falando de tom
  — quem precisa de um específico o diz. O `:status` também entra por aqui: é
  como se exercitam "pronta" e "arquivada", que nesta história ainda não nascem
  pela tela, sem marcar as linhas do rótulo como código morto.
  """
  def band_repertoire_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {band, attrs} = Map.pop_lazy(attrs, :band, &band_fixture/0)
    {song, attrs} = Map.pop_lazy(attrs, :song, &song_fixture/0)

    attrs = Enum.into(attrs, %{key: "C"})

    {:ok, entry} = Repertoire.add_song_to_band(band, song.id, attrs)
    entry
  end
end
