defmodule ChurchBandsWeb.NotificationLive.Index do
  @moduledoc """
  A central de notificações de quem está olhando (US 4.5).

  **Cada um vê só as suas, e nem acesso total vê as dos outros.** O recorte é a
  **consulta** — `Notifications.list_for_user/1` e `get_for_user/2` —, e não um
  hook: não há id na rota para alguém forçar. Quem forçar o id de uma
  notificação de outra pessoa pelo socket recebe a **mesma** recusa do id
  inventado, <q>Notificação não encontrada.</q>, porque dizer <q>existe, mas
  não é sua</q> já contaria alguma coisa sobre a vida de terceiros.

  **Abrir marca como lida e leva ao caminho da notificação**, nessa ordem. A
  ida é um `redirect/2`, e não um `push_navigate/2`, por duas razões: o `path` é
  genérico por desenho — a tabela não guarda de que assunto a linha nasceu, e os
  destinos vão crescer —, e `push_navigate/2` só atravessa rotas da mesma
  `live_session`. O carregamento inteiro é também o que faz o sino da tela de
  destino já chegar com o número certo.

  **O contador da moldura é recontado aqui**, e não no banco: a lista já veio
  inteira, e contar em Elixir o que está na mão é de graça. É o que faz
  *Marcar todas como lidas* zerar o sino no mesmo clique, em vez de só na
  próxima navegação.

  **Quem desenha cada linha é `NotificationComponents.notification_line/1`**,
  a mesma do resumo da home (US 4.6): o destaque de não lida é a mesma
  informação nas duas telas, e informação igual não pode ter duas aparências.
  O que muda é só o que envolve a linha — aqui um botão, lá um link `POST`.

  **A lista se recarrega sozinha (#112)**, pela mesma campainha do sino
  (`Realtime.notifications_topic/1`, assinada em `Notifications.notify/3`):
  chegar aqui e ver uma notificação nova aparecer sem F5 não é um caso
  especial — é o mesmo tópico que `SwapLive.Index` também escuta.
  """
  use ChurchBandsWeb, :live_view

  import ChurchBandsWeb.NotificationComponents

  alias ChurchBands.Notifications
  alias ChurchBands.Realtime

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Realtime.subscribe(Realtime.notifications_topic(socket.assigns.current_user))
    end

    {:ok,
     socket
     |> assign(:page_title, "Notificações")
     |> load_notifications()}
  end

  @impl true
  def handle_info(:notifications_updated, socket) do
    {:noreply, load_notifications(socket)}
  end

  # Ver o comentário gêmeo em `SwapLive.Index`: sem esta cláusula, qualquer
  # mensagem que não seja `:notifications_updated` derrubaria a LiveView.
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Notifications.get_for_user(user, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Notificação não encontrada.")
         |> load_notifications()}

      notification ->
        Notifications.mark_read(user, notification)
        {:noreply, redirect(socket, to: notification.path)}
    end
  end

  def handle_event("mark_all_read", _params, socket) do
    Notifications.mark_all_read(socket.assigns.current_user)

    {:noreply,
     socket
     |> put_flash(:info, "Todas as notificações foram marcadas como lidas.")
     |> load_notifications()}
  end

  defp load_notifications(socket) do
    notifications = Notifications.list_for_user(socket.assigns.current_user)

    socket
    |> assign(:notifications, notifications)
    |> assign(:unread_notifications, Enum.count(notifications, &is_nil(&1.read_at)))
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
      breadcrumb={[{"Notificações", nil}]}
    >
      <:actions>
        <%!-- Sem não lidas o botão não aparece: oferecer uma ação que não faz
        nada é pior do que não a oferecer. --%>
        <.button
          :if={@unread_notifications > 0}
          id="mark-all-read"
          variant="outline"
          size="sm"
          phx-click="mark_all_read"
        >
          Marcar todas como lidas
        </.button>
      </:actions>

      <.header>
        Notificações
        <:subtitle>
          O que aconteceu com você, da mais recente para a mais antiga. O e-mail continua
          chegando — esta lista não o substitui.
        </:subtitle>
      </.header>

      <ul
        :if={@notifications != []}
        id="notifications"
        class="divide-border mt-6 divide-y text-sm"
      >
        <li :for={notification <- @notifications}>
          <%!-- É um botão, e não um link: abrir uma notificação **escreve** —
          ela fica lida —, e só depois leva ao caminho dela. --%>
          <button
            type="button"
            id={"notification-#{notification.id}"}
            phx-click="open"
            phx-value-id={notification.id}
            class="hover:bg-muted -mx-2 flex w-[calc(100%+1rem)] items-start gap-3 rounded-md px-2 py-3 text-left"
          >
            <.notification_line notification={notification} />
          </button>
        </li>
      </ul>

      <p
        :if={@notifications == []}
        id="notifications-empty"
        class="text-muted-foreground mt-6 text-sm"
      >
        Nenhuma notificação por aqui.
      </p>
    </Layouts.app>
    """
  end
end
