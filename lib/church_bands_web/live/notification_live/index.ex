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
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.LocalTime
  alias ChurchBands.Notifications

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Notificações")
     |> load_notifications()}
  end

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
            <span class={[
              "mt-1.5 size-2 shrink-0 rounded-full",
              (is_nil(notification.read_at) && "bg-primary") || "bg-transparent"
            ]} />

            <span class="flex min-w-0 flex-1 flex-col gap-1">
              <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span class={["font-medium", is_nil(notification.read_at) || "text-muted-foreground"]}>
                  {notification.title}
                </span>
                <.badge
                  :if={is_nil(notification.read_at)}
                  id={"notification-unread-#{notification.id}"}
                >
                  Não lida
                </.badge>
              </span>
              <span class="text-muted-foreground">{notification.body}</span>
              <span class="text-muted-foreground text-xs">
                {LocalTime.format(notification.inserted_at, :short)}
              </span>
            </span>
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
