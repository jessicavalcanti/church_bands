defmodule ChurchBandsWeb.EventLive.Show do
  @moduledoc """
  Detalhe de um evento da agenda (US 3.2) — restrita a Pastor e Líder de Louvor
  pelo hook `:ensure_full_access` da `live_session`. A leitura abre para todos
  na US 3.3.

  É a tela das ações: **Editar**, **Cancelar** / **Reabrir** e **Excluir**.

  **Cancelar e reabrir são um par mutuamente exclusivo pelo status**, e não um
  botão que alterna: o rótulo diz o que vai acontecer, e num evento que a
  igreja divulgou não se clica em "alternar" por engano.

  **Cancelar preserva e excluir apaga**, e as duas coisas existem porque são
  perguntas diferentes. Cancelar é "não vai ter" — e o evento continua no
  calendário, riscado, senão quem não olhar de novo aparece no domingo.
  Excluir é "isto nunca deveria existir", e é por isso que a confirmação nomeia
  o evento.

  A tela não reconfere permissão nos eventos porque é de acesso total inteira:
  seria um `if` que nenhum caminho alcança. A reconferência entra na US 3.3,
  quando a leitura abrir e passar a haver quem veja a tela sem poder agir nela
  — é o cuidado que `BandLive.Show` já toma.

  É aqui que nascem o bloco de bandas escaladas (US 3.4) e o set (US 3.7).
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Schedule.get_event(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Evento não encontrado.")
         |> push_navigate(to: ~p"/calendar")}

      event ->
        {:ok, assign_event(socket, event)}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:ok, event} = Schedule.cancel_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Evento #{event.title} cancelado.")
     |> assign_event(event)}
  end

  def handle_event("reopen", _params, socket) do
    {:ok, event} = Schedule.reopen_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Evento #{event.title} reaberto.")
     |> assign_event(event)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, event} = Schedule.delete_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Evento #{event.title} excluído.")
     |> push_navigate(to: ~p"/calendar")}
  end

  defp assign_event(socket, event) do
    socket
    |> assign(:event, event)
    |> assign(:page_title, event.title)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[{"Calendário", ~p"/calendar"}, {@event.title, nil}]}
    >
      <:actions>
        <.link
          id="back-to-calendar"
          navigate={~p"/calendar"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar
        </.link>
        <.link
          id="edit-event"
          navigate={~p"/events/#{@event.id}/edit"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          Editar
        </.link>
        <.button
          :if={@event.status == :scheduled}
          id="cancel-event"
          variant="outline"
          size="sm"
          phx-click="cancel"
          data-confirm={"Cancelar o evento #{@event.title}? Ele continua no calendário, riscado."}
        >
          Cancelar evento
        </.button>
        <.button
          :if={@event.status == :cancelled}
          id="reopen-event"
          variant="outline"
          size="sm"
          phx-click="reopen"
          data-confirm={"Reabrir o evento #{@event.title}?"}
        >
          Reabrir
        </.button>
        <.button
          id="delete-event"
          variant="destructive"
          size="sm"
          phx-click="delete"
          data-confirm={"Excluir o evento #{@event.title}? Isto não dá para desfazer."}
        >
          Excluir
        </.button>
      </:actions>

      <.header>
        <span class={@event.status == :cancelled && "line-through"}>{@event.title}</span>
        <:subtitle>
          <.badge variant="secondary">{@event.event_type.name}</.badge>
          <.badge :if={@event.status == :cancelled} id="event-cancelled-badge" variant="outline">
            Cancelado
          </.badge>
        </:subtitle>
      </.header>

      <dl class="divide-border mt-6 divide-y text-sm">
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Data</dt>
          <dd id="event-date" class="text-right font-medium">
            {LocalTime.format(@event.starts_at, :date)}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Hora</dt>
          <dd id="event-time" class="text-right font-medium">
            {LocalTime.format(@event.starts_at, :time)}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Local</dt>
          <dd id="event-location" class="text-right">
            <span :if={@event.location} class="font-medium">{@event.location}</span>
            <span :if={is_nil(@event.location)} class="text-muted-foreground italic">
              Não informado
            </span>
          </dd>
        </div>
      </dl>

      <div :if={@event.notes} class="mt-8">
        <.header>
          Observações
          <:subtitle>O que quem está escalado precisa saber.</:subtitle>
        </.header>
        <p id="event-notes" class="mt-3 text-sm whitespace-pre-line">{@event.notes}</p>
      </div>
    </Layouts.app>
    """
  end
end
