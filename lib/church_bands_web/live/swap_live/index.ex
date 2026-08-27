defmodule ChurchBandsWeb.SwapLive.Index do
  @moduledoc """
  Os pedidos de troca de escala de quem está olhando (US 4.2): os que ele
  enviou e os que recebeu.

  **Cada um vê só os seus, e nem acesso total vê os dos outros.** Não é
  esquecimento: um pedido de troca é acordo entre duas pessoas, e a tela que o
  lista é a caixa de entrada delas. Por isso o recorte é a **consulta**
  (`Swaps.list_sent/1` e `list_received/1`), e não um hook — não há id na rota
  para alguém forçar.

  **Desde a US 4.3 é aqui que se responde.** Cada pedido recebido e ainda
  pendente ganha três botões — **Só cobrir**, **Trocar o dia** e **Recusar** —,
  e os dois primeiros são o mesmo `handle_event("accept", ...)` com o modo no
  `phx-value`. *Cobrir* é assumir o dia de quem pediu e manter o seu; *trocar*
  é cada um assumir o compromisso do outro.

  **Trocar o dia só aparece quando é viável**, e a tela diz o motivo quando não
  é: o seu dia foi cancelado ou já passou, quem pediu já está escalado nele, a
  sua vaga já foi trocada, ou ele ficaria com dois compromissos perto demais.
  Nos quatro casos **cobrir e recusar continuam** — quem está com o próprio
  culto cancelado ficou mais livre para cobrir o outro, não menos. Quem responde é
  `Swaps.swap_mode_available/1`, e é a mesma pergunta que o servidor refaz
  dentro da transação do aceite — **esconder o botão nunca foi autorização**, e
  o mundo pode mudar entre a tela carregar e o clique.

  **A pergunta é por pedido pendente, e não por linha da lista.** Uma caixa de
  entrada de troca tem o tamanho de uma pessoa, não de uma igreja: quem tem
  três pedidos esperando resposta paga três perguntas, e quem não tem nenhum
  não paga nenhuma.

  **Cancelar é só do solicitante, e só enquanto o pedido está pendente**, e a
  tela reconfere isso no servidor — `Swaps.cancel_request/2` responde
  `{:error, :ineligible}` ao alvo que dispara o evento pelo socket e ao pedido
  que já está cancelado. Esconder o botão nunca foi autorização.

  **O evento cancelado aparece riscado, e o pedido continua pendente.** Evento
  cancelado se reabre (US 3.4), e apagar o pedido junto tornaria a reabertura
  uma perda silenciosa — responder a pedido de evento cancelado é recusa da
  US 4.3.

  O que **não** aparece aqui é o pedido cuja vaga deixou de existir: desescalar
  a banda ou tirar a pessoa dela apaga a linha, pelo `on_delete: :delete_all`
  das quatro chaves.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Swaps
  alias ChurchBands.Swaps.SwapRequest

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Trocas")
     |> load_requests()}
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    case cancel(socket.assigns.current_user, Swaps.get_request(id)) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pedido de troca cancelado.")
         |> load_requests()}

      # O pedido **já está cancelado** quando isto acontece: cancelar é a ação e
      # avisar é a consequência. Por isso a lista é recarregada como no
      # sucesso, e a mensagem fala do aviso, não do cancelamento.
      {:error, {:delivery_failed, _reason}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Pedido de troca cancelado, mas não foi possível avisar por e-mail."
         )
         |> load_requests()}

      # O alvo disparando o evento pelo socket, o pedido que já está cancelado
      # e o id inventado são a mesma coisa para quem lê: **este pedido não é seu
      # para cancelar**.
      {:error, :ineligible} ->
        {:noreply,
         socket
         |> put_flash(:error, "Não foi possível cancelar este pedido.")
         |> load_requests()}
    end
  end

  # Os dois botões de aceite são o **mesmo** evento com modos diferentes: o que
  # muda entre cobrir e trocar é o alcance da resposta, não a ação. O modo chega
  # como texto do `phx-value` e é peneirado por `SwapRequest.cast_mode/1` —
  # quem dispara o evento pelo socket manda o que quiser.
  def handle_event("accept", %{"id" => id, "mode" => mode}, socket) do
    respond(socket, id, &Swaps.accept_request(&1, &2, mode))
  end

  def handle_event("decline", %{"id" => id}, socket) do
    respond(socket, id, &Swaps.decline_request/2)
  end

  defp cancel(_user, nil), do: {:error, :ineligible}
  defp cancel(user, request), do: Swaps.cancel_request(user, request)

  # As três respostas passam pelo mesmo funil porque erram do mesmo jeito: o
  # contexto reconfere quem responde, o estado do pedido e as duas pontas, e
  # devolve `{:error, :ineligible}` para tudo o que a tela não deveria ter
  # oferecido — o solicitante forçando o próprio pedido, acesso total forçando o
  # de terceiros, o pedido já respondido, o id inventado e o modo forjado.
  defp respond(socket, id, action) do
    case respond_to(socket.assigns.current_user, Swaps.get_request(id), action) do
      {:ok, request} ->
        {:noreply,
         socket
         |> put_flash(:info, response_message(request))
         |> load_requests()}

      # A resposta **já está gravada** quando isto acontece: responder é a ação
      # e avisar é a consequência. Por isso a lista é recarregada como no
      # sucesso, e a mensagem fala do aviso.
      {:error, {:delivery_failed, _reason}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Resposta registrada, mas não foi possível avisar por e-mail.")
         |> load_requests()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, refusal_message(reason))
         |> load_requests()}
    end
  end

  defp respond_to(_user, nil, _action), do: {:error, :ineligible}
  defp respond_to(user, request, action), do: action.(user, request)

  defp response_message(%SwapRequest{status: :accepted, mode: :cover} = request) do
    "Você vai cobrir #{requester_name(request)} em #{event_title(request.requester_event_band)}."
  end

  defp response_message(%SwapRequest{status: :accepted, mode: :swap} = request) do
    "Troca feita com #{requester_name(request)}: você toca em " <>
      "#{event_title(request.requester_event_band)} e ele(a) em " <>
      "#{event_title(request.target_event_band)}."
  end

  defp response_message(%SwapRequest{status: :declined}), do: "Pedido de troca recusado."

  defp refusal_message(:slot_taken), do: "Esta vaga já foi trocada."

  defp refusal_message({:conflict, event}),
    do: "Você já toca em #{event.title}, no mesmo horário."

  defp refusal_message(:ineligible), do: "Este pedido não pode mais ser respondido."

  # O motivo de **Trocar o dia** não estar sendo oferecido, dito do ponto de
  # vista de quem lê a tela: quem fica de fora é sempre o solicitante, e é o
  # nome dele que a frase precisa carregar para a pessoa entender por que só
  # sobrou cobrir.
  defp swap_reason(_request, :target_closed),
    do: "o seu dia deste pedido foi cancelado ou já passou."

  defp swap_reason(request, :already_scheduled),
    do: "#{requester_name(request)} já está escalado(a) no seu evento."

  defp swap_reason(_request, :slot_taken), do: "a sua vaga neste dia já foi trocada."

  defp swap_reason(request, {:conflict, event}),
    do: "#{requester_name(request)} já toca em #{event.title}, no mesmo horário."

  defp requester_name(request), do: request.requester_member.user.name
  defp event_title(event_band), do: event_band.event.title

  defp load_requests(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:sent, Swaps.list_sent(user))
    |> assign(:received, Enum.map(Swaps.list_received(user), &decorate(user, &1)))
  end

  # Cada linha recebida carrega o que a tela precisa decidir: se há botões, e
  # se **Trocar o dia** é um deles. As duas perguntas custam consulta, e por
  # isso a segunda só é feita quando a primeira já disse sim — pedido
  # respondido ou de evento passado não tem botão nenhum para justificar.
  defp decorate(user, request) do
    if Swaps.respond?(user, request) do
      %{request: request, respond?: true, swap: Swaps.swap_mode_available(request)}
    else
      %{request: request, respond?: false, swap: nil}
    end
  end

  # A escala escrita numa linha: o evento, quando ele é, e de que banda é a
  # vaga. O evento cancelado vem riscado — a informação continua valendo, e é
  # justamente por ela continuar valendo que o pedido não some.
  attr :event_band, :map, required: true
  attr :label, :string, required: true
  attr :id, :string, required: true

  defp slot_line(assigns) do
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[{"Trocas", nil}]}
    >
      <.header>
        Trocas de escala
        <:subtitle>
          Os pedidos que você fez e os que fizeram a você. Pedir troca começa no elenco de um
          evento, no calendário.
        </:subtitle>
      </.header>

      <div class="mt-8">
        <.header>
          Pedidos que enviei
          <:subtitle>Um por evento seu, enquanto estiver pendente.</:subtitle>
        </.header>

        <ul :if={@sent != []} id="sent-requests" class="divide-border mt-3 divide-y text-sm">
          <li :for={request <- @sent} id={"sent-request-#{request.id}"} class="py-3">
            <div class="flex items-start justify-between gap-4">
              <div class="space-y-1">
                <p class="font-medium">
                  {request.target_member.user.name} · {BandMember.role_label(request.requester_member)}
                </p>
                <.slot_line
                  id={"sent-origin-#{request.id}"}
                  label="Você não pode:"
                  event_band={request.requester_event_band}
                />
                <.slot_line
                  id={"sent-target-#{request.id}"}
                  label="O dia dele(a):"
                  event_band={request.target_event_band}
                />
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <.badge id={"sent-status-#{request.id}"} variant={badge_variant(request.status)}>
                  {SwapRequest.status_label(request)}
                </.badge>
                <.button
                  :if={request.status == :pending}
                  id={"cancel-request-#{request.id}"}
                  variant="ghost"
                  size="sm"
                  phx-click="cancel"
                  phx-value-id={request.id}
                  data-confirm={"Cancelar o pedido de troca com #{request.target_member.user.name}?"}
                >
                  Cancelar pedido
                </.button>
              </div>
            </div>
          </li>
        </ul>

        <p :if={@sent == []} id="sent-requests-empty" class="text-muted-foreground mt-3 text-sm">
          Você ainda não pediu troca a ninguém.
        </p>
      </div>

      <div class="mt-8">
        <.header>
          Pedidos que recebi
          <:subtitle>
            Cobrir é assumir o dia da outra pessoa e manter o seu. Trocar é cada um assumir o
            compromisso do outro.
          </:subtitle>
        </.header>

        <ul :if={@received != []} id="received-requests" class="divide-border mt-3 divide-y text-sm">
          <li :for={row <- @received} id={"received-request-#{row.request.id}"} class="py-3">
            <div class="flex items-start justify-between gap-4">
              <div class="space-y-1">
                <p class="font-medium">
                  {row.request.requester_member.user.name} · {BandMember.role_label(
                    row.request.requester_member
                  )}
                </p>
                <.slot_line
                  id={"received-origin-#{row.request.id}"}
                  label="Ele(a) não pode:"
                  event_band={row.request.requester_event_band}
                />
                <.slot_line
                  id={"received-target-#{row.request.id}"}
                  label="O seu dia:"
                  event_band={row.request.target_event_band}
                />
                <p
                  :if={row.respond? and row.swap != :ok}
                  id={"swap-unavailable-#{row.request.id}"}
                  class="text-muted-foreground italic"
                >
                  Trocar o dia não é possível: {swap_reason(row.request, elem(row.swap, 1))}
                </p>
              </div>
              <div class="flex shrink-0 flex-col items-end gap-2">
                <.badge
                  id={"received-status-#{row.request.id}"}
                  variant={badge_variant(row.request.status)}
                >
                  {SwapRequest.status_label(row.request)}
                </.badge>
                <div :if={row.respond?} class="flex items-center gap-2">
                  <.button
                    id={"accept-cover-#{row.request.id}"}
                    variant="outline"
                    size="sm"
                    phx-click="accept"
                    phx-value-id={row.request.id}
                    phx-value-mode="cover"
                    data-confirm={cover_confirm(row.request)}
                  >
                    Só cobrir
                  </.button>
                  <.button
                    :if={row.swap == :ok}
                    id={"accept-swap-#{row.request.id}"}
                    variant="outline"
                    size="sm"
                    phx-click="accept"
                    phx-value-id={row.request.id}
                    phx-value-mode="swap"
                    data-confirm={swap_confirm(row.request)}
                  >
                    Trocar o dia
                  </.button>
                  <.button
                    id={"decline-#{row.request.id}"}
                    variant="ghost"
                    size="sm"
                    phx-click="decline"
                    phx-value-id={row.request.id}
                    data-confirm={"Recusar o pedido de troca de #{row.request.requester_member.user.name}?"}
                  >
                    Recusar
                  </.button>
                </div>
              </div>
            </div>
          </li>
        </ul>

        <p
          :if={@received == []}
          id="received-requests-empty"
          class="text-muted-foreground mt-3 text-sm"
        >
          Ninguém pediu troca com você.
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp badge_variant(:pending), do: "default"
  defp badge_variant(:accepted), do: "secondary"
  defp badge_variant(:cancelled), do: "outline"
  defp badge_variant(:declined), do: "outline"

  # A confirmação diz o que cada botão faz, e a diferença entre os dois é
  # exatamente o que se perde clicando no errado: cobrir mantém o seu dia,
  # trocar o entrega.
  defp cover_confirm(request) do
    "Cobrir #{requester_name(request)} em #{event_title(request.requester_event_band)}? " <>
      "O seu dia continua sendo seu."
  end

  defp swap_confirm(request) do
    "Trocar o dia com #{requester_name(request)}? Você passa a tocar em " <>
      "#{event_title(request.requester_event_band)} e ele(a) em " <>
      "#{event_title(request.target_event_band)}."
  end
end
