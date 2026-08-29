defmodule ChurchBandsWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use ChurchBandsWeb, :html

  # As duas peças que a home divide com as telas da Fase 4 (US 4.6): a escala
  # de um pedido de troca, que `/swaps` também escreve, e a linha de uma
  # notificação, que a central também escreve. A mesma informação não pode ter
  # duas aparências.
  import ChurchBandsWeb.NotificationComponents
  import ChurchBandsWeb.SwapComponents

  alias ChurchBands.Bands.BandMember
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

  @doc """
  A frase da troca, do ponto de vista de quem está lendo a própria agenda
  (US 4.4).

  São as duas pontas da mesma troca aceita, e por isso as duas frases: quem
  assumiu lê <q>no lugar de Fulano</q>, o mesmo texto do elenco do evento
  (US 4.3); quem cedeu lê <q>Fulano vai no seu lugar</q>. `nil` não chega aqui
  — a linha só escreve a frase quando há troca.
  """
  def swap_note({:assumed, titular}), do: "no lugar de #{titular.name}"
  def swap_note({:released, substituto}), do: "#{substituto.name} vai no seu lugar"

  @doc """
  Há alguma troca pendente a mostrar, de qualquer das duas pontas?

  É a pergunta que faz o bloco **aparecer**, e não a que o preenche: uma troca
  esperando resposta sua e uma esperando resposta de outra pessoa são coisas
  diferentes na tela, mas para decidir se o bloco existe elas contam igual.
  """
  def pending_swaps?(%{received: received, sent: sent}), do: received != [] or sent != []
end
