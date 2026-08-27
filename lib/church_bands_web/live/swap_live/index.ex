defmodule ChurchBandsWeb.SwapLive.Index do
  @moduledoc """
  Os pedidos de troca de escala de quem está olhando (US 4.2): os que ele
  enviou e os que recebeu.

  **Cada um vê só os seus, e nem acesso total vê os dos outros.** Não é
  esquecimento: um pedido de troca é acordo entre duas pessoas, e a tela que o
  lista é a caixa de entrada delas. Por isso o recorte é a **consulta**
  (`Swaps.list_sent/1` e `list_received/1`), e não um hook — não há id na rota
  para alguém forçar.

  **A lista de recebidos é só leitura nesta história.** Aceitar, recusar e
  escolher entre *só cobrir* e *trocar o dia* são a US 4.3; o que o alvo ganha
  aqui é o e-mail e o lugar onde o pedido aparece. É assim de propósito: o
  pedido precisa existir antes de ter resposta.

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

  defp cancel(_user, nil), do: {:error, :ineligible}
  defp cancel(user, request), do: Swaps.cancel_request(user, request)

  defp load_requests(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:sent, Swaps.list_sent(user))
    |> assign(:received, Swaps.list_received(user))
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
                  {SwapRequest.status_label(request.status)}
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
          <:subtitle>Responder chega na próxima entrega — por enquanto, é só leitura.</:subtitle>
        </.header>

        <ul :if={@received != []} id="received-requests" class="divide-border mt-3 divide-y text-sm">
          <li :for={request <- @received} id={"received-request-#{request.id}"} class="py-3">
            <div class="flex items-start justify-between gap-4">
              <div class="space-y-1">
                <p class="font-medium">
                  {request.requester_member.user.name} · {BandMember.role_label(
                    request.requester_member
                  )}
                </p>
                <.slot_line
                  id={"received-origin-#{request.id}"}
                  label="Ele(a) não pode:"
                  event_band={request.requester_event_band}
                />
                <.slot_line
                  id={"received-target-#{request.id}"}
                  label="O seu dia:"
                  event_band={request.target_event_band}
                />
              </div>
              <.badge id={"received-status-#{request.id}"} variant={badge_variant(request.status)}>
                {SwapRequest.status_label(request.status)}
              </.badge>
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
  defp badge_variant(:cancelled), do: "outline"
end
