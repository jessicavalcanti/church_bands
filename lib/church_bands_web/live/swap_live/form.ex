defmodule ChurchBandsWeb.SwapLive.Form do
  @moduledoc """
  Pedir troca de escala a alguém (US 4.2).

  **É rota própria, e não um modal na tela do evento**: são dois ids a resolver
  antes do mount — o evento e o vínculo do alvo — e uma escolha a fazer, qual
  evento seu entra no lugar. Isso é uma tela, e o caminho é o mesmo de
  `/events/:id/bands/:band_id/set`.

  **Quem decide se ela abre é o hook `:ensure_swap_target`**, e não o `mount/3`:
  quando esta tela roda, `@event` e `@target_member` já passaram por todas as
  regras de elegibilidade. É por isso que aqui não há estado vazio de "nenhum
  evento seu" — sem origem elegível o hook recusa antes, com a mesma mensagem
  que a URL forçada recebe.

  **O formulário não tem changeset**, como o de escalar banda da US 3.4: o que
  ele coleta é uma escolha entre linhas que já existem, e não os campos de um
  registro novo. Quem valida é `Swaps.request_swap/4`, no servidor — o
  `origin_event_band_id` chega como texto e pode ser qualquer texto.

  **Quem tem uma origem só não escolhe nada**: ela aparece escrita, num
  `input` escondido. É o arranjo do seletor de banda da US 3.4 — oferecer um
  seletor de uma opção só é pedir uma decisão que não existe.

  **A entrega do e-mail que falha é dita.** O pedido fica gravado e a tela leva
  para `/swaps` do mesmo jeito — o que falhou foi o aviso —, mas quem pediu lê
  que o e-mail não saiu. É o mesmo cuidado da tela de convites (US 1.1), e vale
  mais aqui: enquanto a notificação dentro da plataforma não existe (US 4.5), o
  e-mail é o único jeito de o alvo descobrir que foi chamado.

  **A tela avisa o que a US 4.3 vai entregar**: quem recebe escolhe entre só
  cobrir o dia e trocar de fato. Dizer isso aqui é o que impede a pessoa de
  achar que já combinou a troca ao clicar em *Enviar pedido*.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Swaps

  @impl true
  def mount(_params, _session, socket) do
    origins = Swaps.list_origin_options(socket.assigns.current_user, socket.assigns.target_member)

    {:ok,
     socket
     |> assign(:page_title, "Pedir troca")
     |> assign(:form, to_form(%{}, as: :swap_request))
     |> assign(:origins, origins)
     |> assign(:single_origin, single(origins))}
  end

  @impl true
  def handle_event("request", %{"swap_request" => %{"origin_event_band_id" => origin_id}}, socket) do
    %{current_user: user, event: event, target_member: target_member} = socket.assigns

    case Swaps.request_swap(user, event, target_member, origin_id) do
      {:ok, request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pedido de troca enviado para #{request.target_member.user.name}.")
         |> push_navigate(to: ~p"/swaps")}

      # O pedido existe, e é por isso que a tela leva para a lista mesmo assim:
      # o que falhou foi o aviso, não a gravação. E o aviso é o que faz o alvo
      # descobrir que foi chamado — enquanto a notificação dentro da plataforma
      # não existe (US 4.5), quem pediu precisa saber que precisa avisar por
      # fora.
      {:error, {:delivery_failed, _reason}} ->
        {:noreply,
         socket
         |> put_flash(:error, delivery_failed_message(socket))
         |> push_navigate(to: ~p"/swaps")}

      # O pendente repetido é a única recusa que a pessoa alcança sem forçar
      # nada: ela tem dois eventos, pediu troca para um e voltou aqui.
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, pending_message(changeset))
         |> push_navigate(to: ~p"/swaps")}

      # Origem forjada, alvo que deixou de ser elegível entre abrir a tela e
      # enviar: para quem lê é a mesma coisa — **este pedido não pode ser
      # feito**. Duas mensagens quase iguais seriam dois textos para manter
      # alinhados sem ninguém para ler a diferença.
      {:error, :ineligible} ->
        {:noreply,
         socket
         |> put_flash(:error, "Você não pode pedir troca com este integrante.")
         |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}")}
    end
  end

  defp delivery_failed_message(socket) do
    "Pedido de troca criado, mas não foi possível enviar o e-mail para " <>
      "#{socket.assigns.target_member.user.name}."
  end

  # A mensagem do índice parcial é escrita no changeset do schema, e é ela que
  # a pessoa lê — repeti-la aqui seria manter dois textos alinhados à mão.
  defp pending_message(changeset) do
    {message, _opts} = changeset.errors[:requester_event_band_id]
    message
  end

  defp single([origin]), do: origin
  defp single(_origins), do: nil

  defp origin_label(origin) do
    "#{origin.event.title} — #{LocalTime.format(origin.event.starts_at, :short)}" <>
      " · #{origin.event_band.band.name}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[
        {"Calendário", ~p"/calendar"},
        {@event.title, ~p"/events/#{@event.id}"},
        {"Pedir troca", nil}
      ]}
    >
      <:actions>
        <.link
          id="back-to-event"
          navigate={~p"/events/#{@event.id}"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar
        </.link>
      </:actions>

      <.header>
        Pedir troca a {@target_member.user.name}
        <:subtitle>
          Diga qual compromisso seu você não pode cumprir. Quem recebe é quem decide.
        </:subtitle>
      </.header>

      <dl class="divide-border mt-6 divide-y text-sm">
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Função</dt>
          <dd id="swap-role" class="text-right font-medium">
            {BandMember.role_label(@target_member)}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Banda</dt>
          <dd id="swap-target-band" class="text-right font-medium">
            {@target_member.band.name}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">O dia dele(a)</dt>
          <dd id="swap-target-event" class="text-right font-medium">
            {@event.title} — {LocalTime.format(@event.starts_at, :short)}
          </dd>
        </div>
      </dl>

      <.form for={@form} id="swap-request-form" phx-submit="request" class="mt-8 space-y-6">
        <.form_item>
          <.form_label field={@form[:origin_event_band_id]}>O dia que você não pode</.form_label>
          <div :if={@single_origin}>
            <input
              type="hidden"
              name={@form[:origin_event_band_id].name}
              value={@single_origin.event_band.id}
            />
            <p id="single-origin" class="text-sm font-medium">{origin_label(@single_origin)}</p>
          </div>
          <.select
            :if={is_nil(@single_origin)}
            field={@form[:origin_event_band_id]}
            prompt="Escolha o compromisso"
            options={Enum.map(@origins, &{origin_label(&1), &1.event_band.id})}
            required
          />
          <p class="text-muted-foreground text-xs">
            Só aparecem os eventos futuros em que você toca a mesma função e {@target_member.user.name} ainda não está escalado(a).
          </p>
        </.form_item>

        <div class="border-border bg-muted/40 rounded-md border p-4 text-sm">
          <p id="swap-notice" class="text-muted-foreground">
            {@target_member.user.name} recebe um e-mail e vê o pedido em <strong>Trocas</strong>.
            Quem recebe é quem escolhe entre <strong>só cobrir</strong>
            o seu dia e <strong>trocar</strong>
            de dia com você.
          </p>
        </div>

        <div class="flex items-center gap-2">
          <.button id="send-swap-request" phx-disable-with="Enviando...">Enviar pedido</.button>
          <.link
            navigate={~p"/events/#{@event.id}"}
            class={button_variant(%{variant: "ghost"})}
          >
            Cancelar
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
