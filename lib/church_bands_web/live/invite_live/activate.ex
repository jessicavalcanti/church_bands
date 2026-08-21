defmodule ChurchBandsWeb.InviteLive.Activate do
  @moduledoc """
  Ativação de conta a partir do link do convite (US 1.2) — acesso público.

  O e-mail da conta vem sempre do convite: o formulário pede apenas nome,
  senha e confirmação. Convites cancelados, já aceitos ou fora do prazo caem
  na tela de link inválido.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, :page_title, "Ativar conta")

    case Accounts.get_usable_invite_by_token(token) do
      nil ->
        {:ok, assign(socket, invite: nil, form: nil)}

      invite ->
        {:ok,
         socket
         |> assign(:invite, invite)
         |> assign(:form, to_form(Accounts.change_user_activation()))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_activation(%User{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.accept_invite(socket.assigns.invite, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Conta ativada, #{user.name}! Faça login para entrar.")
         |> push_navigate(to: ~p"/login?#{[email: user.email]}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}

      {:error, :invalid_invite} ->
        {:noreply, assign(socket, invite: nil, form: nil)}

      {:error, :email_taken} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Este e-mail já possui uma conta. Use a tela de login para entrar."
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <%= if @invite do %>
        <.header class="text-center">
          Ativar conta
          <:subtitle>
            Defina uma senha para <span class="font-semibold">{@invite.email}</span>
            e comece a usar o sistema.
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="activation-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.form_item>
            <.form_label field={@form[:name]}>Seu nome</.form_label>
            <.input field={@form[:name]} type="text" required />
            <.form_message field={@form[:name]} />
          </.form_item>

          <.form_item>
            <.form_label field={@form[:password]}>Senha</.form_label>
            <.input
              field={@form[:password]}
              type="password"
              placeholder="Ao menos 8 caracteres, com letras e números"
              required
            />
            <.form_message field={@form[:password]} />
          </.form_item>

          <.form_item>
            <.form_label field={@form[:password_confirmation]}>Confirme a senha</.form_label>
            <.input field={@form[:password_confirmation]} type="password" required />
            <.form_message field={@form[:password_confirmation]} />
          </.form_item>

          <.button id="activate-account-button" class="w-full" phx-disable-with="Ativando...">
            Ativar conta
          </.button>
        </.form>
      <% else %>
        <div id="invalid-invite" class="space-y-4 text-center">
          <.header class="text-center">
            Link inválido
            <:subtitle>
              Este convite não é mais válido — ele pode ter expirado, sido cancelado ou já ter
              sido usado. Peça um novo convite a quem cuida do grupo de louvor.
            </:subtitle>
          </.header>

          <.link navigate={~p"/login"} class={button_variant(%{variant: "outline"})}>
            Ir para o login
          </.link>
        </div>
      <% end %>
    </Layouts.public>
    """
  end
end
