defmodule ChurchBandsWeb.CalendarLive.Index do
  @moduledoc """
  A agenda da igreja (US 3.2) — restrita a Pastor e Líder de Louvor pelo hook
  `:ensure_full_access` declarado na `live_session` do router.

  **Nasce como lista cronológica, e não como grade.** A grade mensal é da
  US 3.3, junto com a leitura ampla; aqui a tela existe para quem escreve
  conferir o que criou. Fazer a grade antes de haver evento para pôr nela seria
  desenhar o mês vazio duas vezes.

  **O passado não some.** Ele desce para baixo de um separador, porque o
  calendário também é registro: foi o que aconteceu, e não só o que vai
  acontecer. Evento cancelado fica na lista riscado pelo mesmo motivo — quem
  não olhar de novo não pode ser surpreendido no domingo.

  A tela não reconfere permissão nos eventos porque não tem evento nenhum: as
  ações moram em `EventLive.Show`. A reconferência entra na US 3.3, quando a
  leitura abrir e o botão *Novo evento* passar a aparecer só para parte de quem
  vê a lista.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Calendário")
     |> load_events()}
  end

  # A fronteira entre o que vem e o que passou é o instante de agora, e ela é
  # calculada uma vez por carga: perguntar por linha faria dois eventos do
  # mesmo minuto caírem em lados diferentes do separador.
  defp load_events(socket) do
    {upcoming, past} = Enum.split_with(Schedule.list_events(), &upcoming?(&1, LocalTime.now()))

    socket
    |> assign(:upcoming, upcoming)
    |> assign(:past, Enum.reverse(past))
    |> assign(:events_count, length(upcoming) + length(past))
  end

  defp upcoming?(event, now), do: not DateTime.before?(event.starts_at, now)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[{"Calendário", nil}]}
    >
      <:actions>
        <.link id="new-event-button" navigate={~p"/events/new"} class={button_variant(%{size: "sm"})}>
          <.icon name="hero-plus" class="mr-2 size-4" /> Novo evento
        </.link>
      </:actions>

      <.header>
        Calendário
        <:subtitle>
          O que a igreja tem marcado, do próximo ao mais distante. O que já aconteceu fica
          guardado aqui embaixo.
        </:subtitle>
      </.header>

      <div :if={@events_count == 0} id="calendar-empty" class="text-muted-foreground py-8 text-center">
        Nenhum evento no calendário ainda.
      </div>

      <div :if={@upcoming != []} id="upcoming-events" class="mt-6 space-y-3">
        <.event_card :for={event <- @upcoming} event={event} />
      </div>

      <div :if={@past != []} class="mt-10">
        <h2
          id="past-separator"
          class="text-muted-foreground border-border border-b pb-2 text-sm font-medium"
        >
          Já aconteceram
        </h2>
        <div id="past-events" class="mt-3 space-y-3">
          <.event_card :for={event <- @past} event={event} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :event, :map, required: true

  defp event_card(assigns) do
    ~H"""
    <.link id={"event-#{@event.id}"} navigate={~p"/events/#{@event.id}"} class="block">
      <.card class="hover:bg-muted/40 transition-colors">
        <.card_content class="flex flex-wrap items-center justify-between gap-3 py-4">
          <div>
            <p class={["font-medium", @event.status == :cancelled && "line-through"]}>
              {@event.title}
            </p>
            <p class="text-muted-foreground text-sm">
              {LocalTime.format(@event.starts_at, :short)}
              <span :if={@event.location}>· {@event.location}</span>
            </p>
          </div>
          <div class="flex items-center gap-2">
            <.badge variant="secondary">{@event.event_type.name}</.badge>
            <.badge
              :if={@event.status == :cancelled}
              id={"event-cancelled-#{@event.id}"}
              variant="outline"
            >
              Cancelado
            </.badge>
          </div>
        </.card_content>
      </.card>
    </.link>
    """
  end
end
