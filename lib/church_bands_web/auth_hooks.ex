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
  """
  use ChurchBandsWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias ChurchBands.Accounts
  alias ChurchBands.Bands

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

  def on_mount(:ensure_band_editor, %{"id" => id}, session, socket) do
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

      not Bands.edit_band?(socket.assigns.current_user, band) ->
        {:halt,
         socket
         |> put_flash(:error, "Você não tem permissão para editar esta banda.")
         |> redirect(to: ~p"/bands")}

      true ->
        {:cont, assign(socket, :band, band)}
    end
  end

  defp mount_current_user(socket, session) do
    socket
    |> assign_new(:current_user, fn ->
      case session do
        %{"user_id" => user_id} -> Accounts.get_user(user_id)
        %{} -> nil
      end
    end)
    |> then(fn socket ->
      assign_new(socket, :full_access?, fn ->
        Accounts.full_access?(socket.assigns.current_user)
      end)
    end)
  end

  # Quem não está logado vai para o login; quem está mas não tem permissão vai
  # para a home, já que mandá-lo ao login não resolveria nada.
  defp redirect_with_error(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end
end
