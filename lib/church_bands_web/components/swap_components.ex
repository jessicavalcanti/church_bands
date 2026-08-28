defmodule ChurchBandsWeb.SwapComponents do
  @moduledoc """
  A escala escrita numa linha de pedido de troca, compartilhada pelas duas
  telas que mostram um pedido (US 4.6): `SwapLive.Index`, a caixa de entrada
  inteira, e a home, onde só os pendentes aparecem.

  **É a mesma frase nos dois lugares**, e por isso é uma peça só: o evento,
  quando ele é e de que banda é a vaga. O evento **cancelado vem riscado** — a
  informação continua valendo, e é justamente por ela continuar valendo que o
  pedido não some de `/swaps` (US 4.3). Duas escritas discordariam no dia em
  que o risco mudasse de lugar, e a home passaria a mostrar como normal o dia
  que a outra tela mostra cancelado.

  **Quem diz o que a linha é vem de fora**, no `label`: o mesmo evento é
  <q>Você não pode:</q> para quem pediu e <q>Ele(a) não pode:</q> para quem
  recebeu. É o lado de quem lê que muda, não a escala.
  """
  use ChurchBandsWeb, :html

  alias ChurchBands.LocalTime

  @doc """
  Uma das duas escalas de um pedido: o rótulo, o evento com a data e a banda.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :event_band, :map, required: true

  def slot_line(assigns) do
    ~H"""
    <p id={@id} class="text-muted-foreground">
      {@label}
      <span class={@event_band.event.status == :cancelled && "line-through"}>
        {@event_band.event.title} — {LocalTime.format(@event_band.event.starts_at, :short)}
      </span>
      · {@event_band.band.name}
    </p>
    """
  end
end
