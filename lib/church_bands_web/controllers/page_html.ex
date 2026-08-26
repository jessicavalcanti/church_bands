defmodule ChurchBandsWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use ChurchBandsWeb, :html

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule
  alias ChurchBands.Sorting

  embed_templates "page_html/*"

  @doc """
  Os nomes das bandas de uma escala, em ordem alfabética, separados por
  vírgula.

  Mesma forma do `band_names/1` da grade do calendário: a escala já chega
  ordenada do contexto, e `Sorting.by_name/1` aqui é o que garante que ela
  continue ordenada se um dia chegar de outro lugar — a ordem alfabética do
  projeto é sempre em Elixir.
  """
  def band_names(event_bands) do
    event_bands
    |> Enum.map(& &1.band)
    |> Sorting.by_name()
    |> Enum.map_join(", ", & &1.name)
  end
end
