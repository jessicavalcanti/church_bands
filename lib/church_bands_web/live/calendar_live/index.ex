defmodule ChurchBandsWeb.CalendarLive.Index do
  @moduledoc """
  A agenda da igreja em grade mensal.

  **Ler é de qualquer um logado (US 3.3); escrever continua sendo de Pastor e
  Líder de Louvor.** A tela nasceu inteira restrita na US 3.2, como lista
  cronológica para quem escreve conferir o que criou, e abriu aqui — junto com
  a troca da lista pela grade. Quem consulta pensa em mês: "o que tem no
  domingo?", "quando é o próximo ensaio?". A lista respondia a essas duas
  perguntas obrigando a percorrer a agenda inteira.

  **O mês e os filtros moram na URL**, não no socket:
  `?month=2026-09&type=3&band=5`. É `handle_params/3` que carrega a grade — o `mount/3` não consulta evento
  nenhum —, e navegação e filtro são `patch`, não `phx-click`. Assim o mês
  aberto é um endereço que se manda para alguém, o F5 não perde o lugar e o
  botão voltar do navegador desfaz a navegação em vez de sair da tela.

  **A faixa consultada é a da grade inteira, não a do mês**, e é calculada no
  fuso da igreja (`LocalTime.start_of_day/1` e `end_of_day/1`). São as duas
  coisas que fazem o culto das 23h do dia 31 cair na célula certa: a hora, que
  em UTC já é do dia seguinte, e os dias vizinhos, que aparecem na grade e
  precisam vir preenchidos.

  **`+N` expande a célula ali mesmo**, guardando o dia no socket — sem rota
  nova e sem modal. Os dias expandidos são guardados como o texto que veio no
  evento, e não como `Date`: comparar texto com texto dispensa converter o que
  chegou pelo socket, e o que não for um dia da grade simplesmente não casa com
  célula nenhuma.

  **São dois filtros desde a US 3.4**, tipo e banda, e cada evento da célula
  escreve as bandas escaladas abaixo do título. Os nomes vêm pré-carregados na
  mesma consulta dos eventos (`preload(:bands)`): perguntá-los por evento seria
  uma consulta por dia de um mês cheio.

  A tela não tem escrita própria — as ações moram em `EventLive.Show`. Aqui a
  permissão só decide se o botão *Novo evento* aparece, e desde a US 3.4 ela é
  `Schedule.create_events?/1`: quem lidera banda marca o ensaio dela, mesmo sem
  acesso total.

  **A grade se redesenha sozinha (#112).** Um tópico só, sem id — todo evento
  criado, editado, cancelado, reaberto, excluído, escalado ou desescalado
  publica em `Realtime.calendar_topic/0` — porque a grade nunca é de um
  evento: é de todos os do mês.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.LocalTime
  alias ChurchBands.Realtime
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule
  alias ChurchBands.Sorting

  # Quantos eventos a célula mostra antes de resumir o resto em `+N`. Três é o
  # que cabe numa célula de mês sem esticar a linha da semana inteira, e uma
  # igreja raramente passa disso num dia.
  @events_per_cell 3

  # O cabeçalho das colunas é rótulo fixo, e não data formatada: a grade começa
  # sempre no domingo, e nenhuma célula precisa ser convertida para escrever
  # isto. Por isso mora aqui, e não em `LocalTime`.
  @weekdays ~w(dom seg ter qua qui sex sáb)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Realtime.subscribe(Realtime.calendar_topic())

    {:ok,
     socket
     |> assign(:page_title, "Calendário")
     |> assign(:weekdays, @weekdays)
     |> assign(:can_create?, Schedule.create_events?(socket.assigns.current_user))
     |> assign(:event_types, Schedule.list_event_types())
     |> assign(:bands, Bands.list_bands())}
  end

  # A grade se redesenha sozinha (#112) quando qualquer evento muda — criar,
  # editar, cancelar, reabrir, excluir, escalar ou desescalar. `load_month/4`
  # também zera `@expanded_days` a cada chamada, o que é certo vindo de
  # `handle_params/3` (mês ou filtro novo, célula nenhuma deveria nascer
  # aberta) e errado vindo daqui: fecharia sozinho o "+N" que a pessoa tinha
  # aberto por causa de uma escrita que não tem nada a ver com aquele dia.
  @impl true
  def handle_info(:calendar_updated, socket) do
    expanded_days = socket.assigns.expanded_days

    socket =
      socket
      |> load_month(
        socket.assigns.month,
        socket.assigns.selected_type,
        socket.assigns.selected_band
      )
      |> assign(:expanded_days, expanded_days)

    {:noreply, socket}
  end

  # Ver o comentário gêmeo em `SwapLive.Index`: sem esta cláusula, qualquer
  # mensagem que não seja `:calendar_updated` derrubaria a LiveView.
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    month = params |> Map.get("month") |> parse_month() |> month_or_current()

    type = chosen(params["type"], socket.assigns.event_types)
    band = chosen(params["band"], socket.assigns.bands)

    {:noreply, load_month(socket, month, type, band)}
  end

  # O id do filtro é texto que alguém pode ter escrito. `RouteId.get/2` devolve
  # `nil` para o que não é id, e procurar na lista já carregada devolve `nil`
  # para o id que não existe — nos dois casos a grade mostra o mês inteiro. URL
  # torta não vira mês vazio inexplicável.
  defp chosen(param, options) do
    RouteId.get(param || "", fn id -> Enum.find(options, &(&1.id == id)) end)
  end

  @impl true
  def handle_event("expand_day", %{"date" => date}, socket) do
    {:noreply, update(socket, :expanded_days, &MapSet.put(&1, date))}
  end

  # O mês da URL vem como `AAAA-MM`, e o dia 1º completa a data que
  # `Date.from_iso8601/1` sabe ler. Ele é quem recusa tanto o que não é data
  # (`banana`) quanto o que tem forma de data e não existe (`2026-13`) —
  # `String.to_integer/1` aceitaria o mês 13 e só estouraria mais adiante.
  defp parse_month(month) when is_binary(month) do
    case Date.from_iso8601(month <> "-01") do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  # Sem `?month=` na URL, e para qualquer coisa que não seja texto.
  defp parse_month(_month), do: :error

  defp month_or_current({:ok, date}), do: date
  defp month_or_current(:error), do: Date.beginning_of_month(LocalTime.today())

  defp load_month(socket, month, type, band) do
    days = grid_days(month)

    events =
      Schedule.list_events(
        from: LocalTime.start_of_day(List.first(days)),
        to: LocalTime.end_of_day(List.last(days)),
        type_id: type && type.id,
        band_id: band && band.id
      )

    socket
    |> assign(:month, month)
    |> assign(:selected_type, type)
    |> assign(:selected_band, band)
    |> assign(:days, days)
    |> assign(:today, LocalTime.today())
    |> assign(:events_count, length(events))
    # O evento é agrupado pelo dia que ele é **na igreja**, e não pela data do
    # instante UTC: o culto das 23h de 31 de agosto está gravado em setembro.
    |> assign(:events_by_day, Enum.group_by(events, &LocalTime.to_date(&1.starts_at)))
    # Trocar de mês ou de filtro redesenha a grade, e nenhuma célula nova nasce
    # expandida.
    |> assign(:expanded_days, MapSet.new())
  end

  # Os dias que a grade desenha: de domingo a sábado, cobrindo o mês inteiro e
  # completando a primeira e a última semana com os dias vizinhos.
  defp grid_days(month) do
    first = month |> Date.beginning_of_month() |> Date.beginning_of_week(:sunday)
    last = month |> Date.end_of_month() |> Date.end_of_week(:sunday)

    first |> Date.range(last) |> Enum.to_list()
  end

  # O mês vai **sempre** para o endereço, mesmo sendo o corrente: o que a tela
  # mostra é um mês, e `/calendar` sozinho é "o mês de quem abrir" — não serve
  # para mandar para alguém. Os filtros, esses só entram quando estreitam
  # alguma coisa.
  defp calendar_path(month, type, band) do
    params =
      [month: Calendar.strftime(month, "%Y-%m"), type: type && type.id, band: band && band.id]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    ~p"/calendar?#{params}"
  end

  # Os dois filtros são a mesma barra de pastilhas com listas diferentes: uma
  # opção que limpa e uma por item. Montar as opções antes de desenhar é o que
  # deixa a barra ser uma só — entre tipo e banda muda apenas o que entra na
  # URL, e não a forma de escolher.
  defp filter_options(all_label, options, selected, path) do
    [%{id: nil, name: all_label, path: path.(nil), selected?: is_nil(selected)}] ++
      Enum.map(options, fn option ->
        %{
          id: option.id,
          name: option.name,
          path: path.(option),
          selected?: selected != nil and selected.id == option.id
        }
      end)
  end

  # As bandas escaladas escrevem o nome abaixo do título, na ordem alfabética
  # do projeto — a mesma de `list_event_bands/1`, que a tela do evento usa.
  defp band_names(bands), do: bands |> Sorting.by_name() |> Enum.map_join(", ", & &1.name)

  defp events_of(events_by_day, day), do: Map.get(events_by_day, day, [])

  defp expanded?(expanded_days, day), do: MapSet.member?(expanded_days, Date.to_iso8601(day))

  # A célula expandida mostra tudo; a fechada mostra o começo e diz quantos
  # ficaram de fora.
  defp visible_events(events, true), do: {events, 0}

  defp visible_events(events, false) do
    {shown, hidden} = Enum.split(events, @events_per_cell)
    {shown, length(hidden)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={[{"Calendário", nil}]}
    >
      <:actions>
        <.link
          :if={@can_create?}
          id="new-event-button"
          navigate={~p"/events/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Novo evento
        </.link>
      </:actions>

      <.header>
        Calendário
        <:subtitle>O que a igreja tem marcado, mês a mês.</:subtitle>
      </.header>

      <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
        <h2 id="calendar-month" class="text-lg font-medium capitalize">
          {LocalTime.format_month(@month)}
        </h2>

        <div class="flex items-center gap-2">
          <.link
            id="previous-month"
            patch={calendar_path(Date.shift(@month, month: -1), @selected_type, @selected_band)}
            aria-label="Mês anterior"
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <.link
            id="current-month"
            patch={calendar_path(Date.beginning_of_month(@today), @selected_type, @selected_band)}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Hoje
          </.link>
          <.link
            id="next-month"
            patch={calendar_path(Date.shift(@month, month: 1), @selected_type, @selected_band)}
            aria-label="Mês seguinte"
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>

      <.filter_bar
        :if={@event_types != []}
        id="type-filter"
        prefix="filter-type-"
        options={
          filter_options(
            "Todos",
            @event_types,
            @selected_type,
            &calendar_path(@month, &1, @selected_band)
          )
        }
      />

      <.filter_bar
        :if={@bands != []}
        id="band-filter"
        prefix="filter-band-"
        options={
          filter_options(
            "Todas as bandas",
            @bands,
            @selected_band,
            &calendar_path(@month, @selected_type, &1)
          )
        }
      />

      <div
        :if={@events_count == 0 and (@selected_type != nil or @selected_band != nil)}
        id="calendar-filtered-empty"
        class="text-muted-foreground mt-4 text-center text-sm"
      >
        Nenhum evento neste mês para o filtro escolhido.
      </div>

      <div id="calendar-grid" class="border-border mt-4 overflow-hidden rounded-lg border">
        <div class="text-muted-foreground grid grid-cols-7 text-center text-xs font-medium">
          <div :for={weekday <- @weekdays} class="border-border border-b px-1 py-2">
            {weekday}
          </div>
        </div>

        <div class="grid grid-cols-7">
          <.day_cell
            :for={day <- @days}
            day={day}
            month={@month}
            today={@today}
            events={events_of(@events_by_day, day)}
            expanded?={expanded?(@expanded_days, day)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :prefix, :string, required: true
  attr :options, :list, required: true

  defp filter_bar(assigns) do
    ~H"""
    <div id={@id} class="mt-3 flex flex-wrap gap-2">
      <.link
        :for={option <- @options}
        id={"#{@prefix}#{option.id || "all"}"}
        patch={option.path}
        aria-current={option.selected? && "true"}
        class="focus-visible:ring-ring/50 rounded-full focus:outline-hidden focus-visible:ring-[3px]"
      >
        <.badge variant={if option.selected?, do: "default", else: "outline"}>
          {option.name}
        </.badge>
      </.link>
    </div>
    """
  end

  attr :day, Date, required: true
  attr :month, Date, required: true
  attr :today, Date, required: true
  attr :events, :list, required: true
  attr :expanded?, :boolean, required: true

  defp day_cell(assigns) do
    {shown, hidden} = visible_events(assigns.events, assigns.expanded?)

    assigns =
      assigns
      |> assign(:shown, shown)
      |> assign(:hidden, hidden)
      # O dia vizinho é o que completa a semana e pertence a outro mês. Ele
      # aparece apagado porque está ali para a semana fechar, não para ser
      # lido como parte deste mês.
      |> assign(:neighbour?, assigns.day.month != assigns.month.month)
      |> assign(:today?, assigns.day == assigns.today)

    ~H"""
    <div
      id={"day-#{Date.to_iso8601(@day)}"}
      class={[
        "border-border min-h-24 border-r border-b p-1 last:border-r-0",
        @neighbour? && "bg-muted/30"
      ]}
    >
      <span class={[
        "inline-flex size-6 items-center justify-center rounded-full text-xs",
        @neighbour? && "text-muted-foreground",
        @today? && "bg-primary text-primary-foreground font-medium"
      ]}>
        {@day.day}
      </span>

      <div class="mt-1 space-y-0.5">
        <.link
          :for={event <- @shown}
          id={"day-event-#{event.id}"}
          navigate={~p"/events/#{event.id}"}
          class="hover:bg-muted block truncate rounded px-1 py-0.5 text-xs"
          title={event.title}
        >
          <span class={event.status == :cancelled && "line-through"}>
            <span class="text-muted-foreground">{LocalTime.format(event.starts_at, :time)}</span>
            {event.title}
          </span>
          <span
            :if={event.status == :cancelled}
            id={"day-event-cancelled-#{event.id}"}
            class="text-muted-foreground text-[10px] uppercase"
          >
            Cancelado
          </span>
          <span
            :if={event.bands != []}
            id={"day-event-bands-#{event.id}"}
            class="text-muted-foreground block truncate text-[10px]"
          >
            {band_names(event.bands)}
          </span>
        </.link>
      </div>

      <button
        :if={@hidden > 0}
        type="button"
        id={"expand-day-#{Date.to_iso8601(@day)}"}
        phx-click="expand_day"
        phx-value-date={Date.to_iso8601(@day)}
        class="text-muted-foreground hover:text-foreground mt-0.5 px-1 text-xs"
      >
        +{@hidden}
      </button>
    </div>
    """
  end
end
