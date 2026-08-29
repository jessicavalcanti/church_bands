defmodule ChurchBandsWeb.AuthHooks do
  @moduledoc """
  Hooks `on_mount` de autenticação e autorização para LiveViews.

  Regra central do sistema: **leitura ampla, escrita restrita**. Toda LiveView
  de escrita precisa passar por um destes hooks — esconder o botão na tela
  nunca é suficiente.

  Hooks disponíveis:

    * `:mount_current_user` — só carrega `current_user` (pode ser `nil`)
    * `:ensure_authenticated` — exige um usuário logado
    * `:ensure_full_access` — exige Pastor ou Líder de Louvor
    * `:ensure_band_editor` — exige poder editar a banda de `:id`, carregando-a
      em `@band` (Pastor, Líder de Louvor ou o próprio Líder da Banda)
    * `:ensure_band_member_manager` — exige poder mexer nos integrantes da banda
      de `:id`, carregando-a em `@band` (mesmo grupo de pessoas)
    * `:ensure_band_repertoire_manager` — exige poder montar o repertório da
      banda de `:id`, carregando-a em `@band` (mesmo grupo de pessoas)
    * `:ensure_user_manager` — exige poder editar os dados da pessoa de `:id`,
      carregando-a em `@user` (Pastor e Líder de Louvor)
    * `:ensure_event_creator` — exige poder marcar algum evento (acesso total,
      ou quem lidera alguma banda)
    * `:ensure_event_manager` — exige poder editar o evento de `:id`,
      carregando-o em `@event` (acesso total, ou o Líder de Banda de uma banda
      escalada nele, se o tipo permitir)
    * `:ensure_event_band` — exige um usuário logado e uma banda **escalada**
      no evento, carregando `@event`, `@event_band` e `@band`. Não pergunta
      nada sobre quem montou o set: ler é de qualquer um logado (US 3.7), e
      quem escreve é `Schedule.manage_set?/2`, na própria tela
    * `:ensure_swap_target` — exige que `@target_member`, o vínculo de `:member_id`,
      seja alguém a quem o usuário pode pedir troca no evento de `:id`
      (US 4.2), carregando `@event` e `@target_member`
  """
  use ChurchBandsWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias ChurchBands.Accounts
  alias ChurchBands.Bands
  alias ChurchBands.Notifications
  alias ChurchBands.Realtime
  alias ChurchBands.Schedule
  alias ChurchBands.Swaps
  alias ChurchBandsWeb.UserAuth

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}
    end
  end

  def on_mount(:ensure_full_access, _params, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      not socket.assigns.full_access? ->
        {:halt,
         socket
         |> put_flash(:error, "Você não tem permissão para acessar esta página.")
         |> redirect(to: ~p"/")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:ensure_user_manager, %{"id" => id}, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      not Accounts.manage_users?(socket.assigns.current_user) ->
        {:halt, denied(socket, "Você não tem permissão para editar os dados de outra pessoa.")}

      true ->
        # A lista de pessoas é aberta a qualquer usuário logado, então o
        # usuário só é buscado depois da permissão — quem não pode editar sai
        # daqui sem nem saber se aquele id existe.
        case Accounts.get_user(id) do
          nil -> {:halt, denied(socket, "Usuário não encontrado.")}
          user -> {:cont, assign(socket, :user, user)}
        end
    end
  end

  # Os dois hooks de evento não passam por `ensure_band_permission/5`: lá o
  # recurso é sempre a banda de `:id`, e a recusa devolve para `/bands`. Aqui o
  # recurso é o evento, a recusa devolve para `/calendar`, e um deles nem tem
  # `:id` para carregar.
  def on_mount(:ensure_event_creator, _params, session, socket) do
    socket = mount_current_user(socket, session)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      not Schedule.create_events?(socket.assigns.current_user) ->
        {:halt,
         socket
         |> put_flash(:error, "Você não tem permissão para acessar esta página.")
         |> redirect(to: ~p"/")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:ensure_event_manager, %{"id" => id}, session, socket) do
    socket = mount_current_user(socket, session)
    event = Schedule.get_event(id)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      is_nil(event) ->
        {:halt, event_denied(socket, "Evento não encontrado.")}

      not Schedule.manage_event?(socket.assigns.current_user, event) ->
        {:halt, event_denied(socket, "Você não tem permissão para gerenciar este evento.")}

      true ->
        {:cont, assign(socket, :event, event)}
    end
  end

  # O que a tela do set precisa saber antes de abrir: **existe este par evento ×
  # banda?**. Nasceu na US 3.6 perguntando também de quem era o set, e a US 3.7
  # tirou essa pergunta daqui: o set virou leitura ampla, e quem pode escrever
  # nele é `Schedule.manage_set?/2`, chamada pela tela e por cada
  # `handle_event`. É o mesmo caminho que `/bands/:id/repertoire` percorreu
  # entre as US 2.2 e 2.6.
  #
  # Ele continua sendo um hook, e não um `mount/3` como o do repertório, porque
  # o par é de **duas** alturas: o evento precisa existir e a banda precisa
  # estar escalada nele, e as duas recusas devolvem para lugares diferentes.
  #
  # Os dois ids vêm da rota como texto, e `Schedule.get_event/1` e
  # `get_event_band/2` já os convertem por `RouteId`: `/events/abc/bands/xyz/set`
  # cai na recusa de evento inexistente, e não num `Ecto.Query.CastError`.
  def on_mount(:ensure_event_band, %{"id" => id, "band_id" => band_id}, session, socket) do
    socket = mount_current_user(socket, session)
    event = Schedule.get_event(id)
    event_band = event && Schedule.get_event_band(event.id, band_id)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      is_nil(event) ->
        {:halt, event_denied(socket, "Evento não encontrado.")}

      is_nil(event_band) ->
        {:halt, set_denied(socket, event, "Esta banda não está escalada neste evento.")}

      true ->
        {:cont,
         socket
         |> assign(:event, event)
         |> assign(:event_band, event_band)
         |> assign(:band, event_band.band)}
    end
  end

  # A tela de pedir troca resolve **dois** ids antes do mount, como
  # `:ensure_event_band`: o evento e o vínculo do alvo. E como lá, os dois vêm
  # da rota como texto e passam por `ChurchBands.RouteId` dentro de
  # `Schedule.get_event/1` e `Bands.get_member/1` — `/events/abc/members/xyz/swap`
  # cai na recusa de <q>Evento não encontrado.</q>, e não num
  # `Ecto.Query.CastError`.
  #
  # São três recusas depois da de quem não está logado, e a ordem delas é o que
  # faz cada uma dizer o que realmente aconteceu:
  #
  #   * o vínculo não existe, ou é de banda que não toca neste evento — para
  #     quem forçou a URL as duas coisas são a mesma: **este integrante não está
  #     aqui**
  #   * a função é outra, que é o engano honesto de quem clicou na pessoa errada
  #   * o resto — o alvo é você, o evento já passou ou foi cancelado, não sobrou
  #     evento seu para oferecer —, que `Swaps.can_request?/3` resolve numa
  #     pergunta só
  #
  # Esconder o botão *Solicitar troca* na tela do evento nunca foi autorização:
  # o caminho de quem digita a URL é este.
  def on_mount(:ensure_swap_target, %{"id" => id, "member_id" => member_id}, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user
    event = Schedule.get_event(id)
    target_member = event && Bands.get_member(member_id)
    scheduled? = target_member && Schedule.get_event_band(event.id, target_member.band_id)

    cond do
      is_nil(user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      is_nil(event) ->
        {:halt, event_denied(socket, "Evento não encontrado.")}

      is_nil(scheduled?) ->
        {:halt, swap_denied(socket, event, "Integrante não encontrado.")}

      not Swaps.shares_role?(user, target_member) ->
        {:halt, swap_denied(socket, event, "Vocês não fazem a mesma função.")}

      not Swaps.can_request?(user, event, target_member) ->
        {:halt, swap_denied(socket, event, "Você não pode pedir troca com este integrante.")}

      true ->
        {:cont,
         socket
         |> assign(:event, event)
         |> assign(:target_member, target_member)}
    end
  end

  def on_mount(:ensure_band_editor, %{"id" => id}, session, socket) do
    ensure_band_permission(
      socket,
      session,
      id,
      &Bands.edit_band?/2,
      "Você não tem permissão para editar esta banda."
    )
  end

  def on_mount(:ensure_band_member_manager, %{"id" => id}, session, socket) do
    ensure_band_permission(
      socket,
      session,
      id,
      &Bands.manage_members?/2,
      "Você não tem permissão para gerenciar os integrantes desta banda."
    )
  end

  def on_mount(:ensure_band_repertoire_manager, %{"id" => id}, session, socket) do
    ensure_band_permission(
      socket,
      session,
      id,
      &Bands.manage_repertoire?/2,
      "Você não tem permissão para gerenciar o repertório desta banda."
    )
  end

  # As permissões por banda seguem todas a mesma sequência — carregar o usuário,
  # carregar a banda, perguntar ao contexto — e mudam só no predicado e na
  # mensagem de recusa.
  defp ensure_band_permission(socket, session, id, permitted?, denied_message) do
    socket = mount_current_user(socket, session)
    band = Bands.get_band(id)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect_with_error(socket, "Você precisa entrar para acessar esta página.")}

      is_nil(band) ->
        {:halt,
         socket
         |> put_flash(:error, "Banda não encontrada.")
         |> redirect(to: ~p"/bands")}

      not permitted?.(socket.assigns.current_user, band) ->
        {:halt,
         socket
         |> put_flash(:error, denied_message)
         |> redirect(to: ~p"/bands")}

      true ->
        {:cont, assign(socket, :band, band)}
    end
  end

  # Recusa das telas de evento: devolve para o calendário, que é aberto a
  # qualquer usuário logado — mandá-lo para a home esconderia dele justamente a
  # tela que ele pode ver.
  defp event_denied(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/calendar")
  end

  # Recusa do set: devolve para o **evento**, e não para o calendário. Quem
  # chegou pela URL do set já sabe qual culto é — mandá-lo dois passos para
  # trás o faria refazer o caminho que acabou de andar. A tela do evento é de
  # leitura ampla desde a US 3.3, então ela sempre abre para quem chega aqui —
  # e desde a US 3.7 é lá que o set aparece de qualquer jeito.
  defp set_denied(socket, event, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/events/#{event.id}")
  end

  # Recusa do pedido de troca: irmã de `set_denied/3`, e pelo mesmo motivo —
  # quem chegou pela URL da troca já sabe qual culto é, e mandá-lo dois passos
  # para trás o faria refazer o caminho. É também de lá que ele vai tentar de
  # novo, na pessoa certa.
  defp swap_denied(socket, event, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/events/#{event.id}")
  end

  # Recusa da edição de pessoas: devolve para a lista, que é o que quem tentou
  # editar realmente pode ver.
  defp denied(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users")
  end

  # O item destacado no menu do portal (US 1.9) sai do caminho da tela aberta.
  # Como todo mount passa por aqui, o assign nasce num lugar só, em vez de cada
  # LiveView ter de lembrar de montá-lo.
  defp attach_current_path(socket) do
    attach_hook(socket, :current_path, :handle_params, fn _params, uri, socket ->
      {:cont, assign(socket, :current_path, URI.parse(uri).path)}
    end)
  end

  # A assinatura só entra na passagem conectada (US 4.5 → #112): o mount roda
  # uma vez desconectado e outra conectado, e assinar na primeira inscreveria
  # um processo que já vai morrer em seguida. Quem não está logado não tem
  # tópico nenhum para ouvir.
  defp subscribe_to_notifications(%{assigns: %{current_user: nil}} = socket), do: socket

  defp subscribe_to_notifications(%{assigns: %{current_user: user}} = socket) do
    if connected?(socket), do: Realtime.subscribe(Realtime.notifications_topic(user))
    attach_realtime_notifications(socket)
  end

  # O sino em tempo real (#112): a mesma campainha que `SwapLive.Index` e
  # `NotificationLive.Index` ouvem para recarregar suas próprias listas, mas
  # aqui só para recontar `@unread_notifications` — o que faz o sino acender
  # em **qualquer** LiveView do portal, sem cada uma precisar assinar nada.
  # `{:cont, socket}` sempre, porque a mesma mensagem ainda precisa cair no
  # `handle_info` do módulo, para quem também tem lista para recarregar.
  defp attach_realtime_notifications(socket) do
    attach_hook(socket, :realtime_notifications, :handle_info, fn
      :notifications_updated, socket ->
        {:cont,
         assign(
           socket,
           :unread_notifications,
           Notifications.unread_count(socket.assigns.current_user)
         )}

      _message, socket ->
        {:cont, socket}
    end)
  end

  defp mount_current_user(socket, session) do
    socket
    |> assign_new(:current_user, fn -> UserAuth.session_user(session) end)
    |> then(fn socket ->
      assign_new(socket, :full_access?, fn ->
        Accounts.full_access?(socket.assigns.current_user)
      end)
    end)
    # O sino da moldura, contado uma vez por carregamento de página (US 4.5).
    # É o par de `ChurchBandsWeb.UnreadNotifications`, que faz o mesmo pelas
    # telas de controller — o assign tem o **mesmo nome** nos dois caminhos,
    # e é o que faz a home passar `unread` para `Layouts.app/1` como qualquer
    # LiveView. Quem não está logado custa zero consulta.
    |> then(fn socket ->
      assign_new(socket, :unread_notifications, fn ->
        Notifications.unread_count(socket.assigns.current_user)
      end)
    end)
    |> subscribe_to_notifications()
    |> assign_new(:current_path, fn -> "/" end)
    # A escolha de recolher a barra lateral nasce no navegador, vira cookie e
    # chega aqui pela sessão (`ChurchBandsWeb.SidebarState`), para que
    # `Layouts.app/1` mande a barra já recolhida em vez de a corrigir depois.
    # O `||` é a rede para a sessão que não passou pelo plug — não existe barra
    # "sem estado", e o padrão do componente é a expandida.
    |> assign_new(:sidebar_state, fn -> session["sidebar_state"] || "expanded" end)
    |> attach_current_path()
  end

  # Quem não está logado vai para o login; quem está mas não tem permissão vai
  # para a home, já que mandá-lo ao login não resolveria nada.
  defp redirect_with_error(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end
end
