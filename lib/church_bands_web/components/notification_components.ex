defmodule ChurchBandsWeb.NotificationComponents do
  @moduledoc """
  A linha de uma notificação, compartilhada pelas duas telas que a mostram
  (US 4.6): `NotificationLive.Index`, a central, e a home, onde ela aparece
  como resumo das cinco mais recentes.

  **Existe porque a mesma informação não pode ter duas aparências.** O que
  distingue uma notificação por ler de uma já lida — o ponto, o peso do título,
  o rótulo *Não lida* — é justamente o tipo de detalhe que se duplica e depois
  diverge: bastaria a central ganhar um destaque novo para a home continuar
  mostrando o antigo, e as duas telas passariam a discordar sobre o que é
  novidade.

  **O que envolve a linha é de cada tela**, e não é cosmético: na central é um
  `<button>`, porque abrir a notificação **escreve** — ela fica lida — e a
  tela é uma LiveView; na home, que é tela de controller, é um link `POST`
  para `ChurchBandsWeb.NotificationController`, que faz a mesma escrita e
  segue para o caminho da notificação. As duas dão no mesmo para quem clica, e
  é por isso que o miolo é um só.
  """
  use ChurchBandsWeb, :html

  alias ChurchBands.LocalTime

  @doc """
  O miolo de uma linha de notificação: o ponto de não lida, o título com o
  rótulo, o texto e a hora.

  Vai **dentro** do elemento clicável de cada tela, que é quem põe o
  `flex items-start gap-3` em volta — a linha não decide como se chega até ela.
  """
  attr :notification, :map, required: true

  def notification_line(assigns) do
    ~H"""
    <span class={[
      "mt-1.5 size-2 shrink-0 rounded-full",
      (is_nil(@notification.read_at) && "bg-primary") || "bg-transparent"
    ]} />

    <span class="flex min-w-0 flex-1 flex-col gap-1">
      <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
        <%!-- A já lida perde o preto do título, e não o peso: ela continua
        legível, só deixa de disputar atenção com o que ainda não foi visto.
        A condição vai pela **positiva** de propósito — escrita como
        `is_nil(...) || "..."`, ela devolvia `true` quando a notificação estava
        por ler, e o `true` ia parar na lista de classes do elemento. --%>
        <span class={[
          "font-medium",
          not is_nil(@notification.read_at) && "text-muted-foreground"
        ]}>
          {@notification.title}
        </span>
        <.badge
          :if={is_nil(@notification.read_at)}
          id={"notification-unread-#{@notification.id}"}
        >
          Não lida
        </.badge>
      </span>
      <span class="text-muted-foreground">{@notification.body}</span>
      <span class="text-muted-foreground text-xs">
        {LocalTime.format(@notification.inserted_at, :short)}
      </span>
    </span>
    """
  end
end
