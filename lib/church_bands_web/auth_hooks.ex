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
  """
  use ChurchBandsWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias ChurchBands.Accounts
  alias ChurchBands.Bands
  alias ChurchBands.Schedule
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

  defp mount_current_user(socket, session) do
    socket
    |> assign_new(:current_user, fn -> UserAuth.session_user(session) end)
    |> then(fn socket ->
      assign_new(socket, :full_access?, fn ->
        Accounts.full_access?(socket.assigns.current_user)
      end)
    end)
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
