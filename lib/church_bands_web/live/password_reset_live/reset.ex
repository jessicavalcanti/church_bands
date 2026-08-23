defmodule ChurchBandsWeb.PasswordResetLive.Reset do
  @moduledoc """
  Tela "Redefinir senha" (US 1.7) — acesso público, aberta pelo link do e-mail.

  Quem é o dono da senha vem do token, nunca do formulário. Link expirado, já
  usado ou inventado cai na mesma tela de link inválido, com o caminho para
  pedir um novo.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBandsWeb.UserAuth

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, page_title: "Redefinir senha", token: token)

    case Accounts.get_usable_reset_token(token) do
      nil ->
        {:ok, assign(socket, reset_token: nil, form: nil)}

      reset_token ->
        {:ok,
         socket
         |> assign(:reset_token, reset_token)
         |> assign(:form, to_form(Accounts.change_user_password()))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_password(%User{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.reset_password(socket.assigns.token, params) do
      {:ok, user} ->
        # Derrubar sessão é efeito, não dado: fica fora da transação do
        # contexto. A troca de senha, por si só, já invalida todo cookie
        # emitido antes dela — a impressão digital da sessão deixa de bater
        # (`UserAuth.session_user/1`). O broadcast é o que faz a aba que ficou
        # aberta em outro navegador cair **agora**, e não na próxima
        # requisição dela: é para isso que se pede uma senha nova quando se
        # desconfia que entraram na conta.
        UserAuth.disconnect_sessions(user)

        {:noreply,
         socket
         |> put_flash(:info, "Senha redefinida! Faça login com a senha nova.")
         |> push_navigate(to: ~p"/login?#{[email: user.email]}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}

      {:error, :invalid_token} ->
        {:noreply, assign(socket, reset_token: nil, form: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <%= if @reset_token do %>
        <.header class="text-center">
          Redefinir senha
          <:subtitle>
            Escolha a nova senha da conta <span class="font-semibold">{@reset_token.user.email}</span>.
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="password-reset-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.form_item>
            <.form_label field={@form[:password]}>Nova senha</.form_label>
            <.input
              field={@form[:password]}
              type="password"
              placeholder="Ao menos 8 caracteres, com letras e números"
              required
            />
            <.form_message field={@form[:password]} />
          </.form_item>

          <.form_item>
            <.form_label field={@form[:password_confirmation]}>Confirme a nova senha</.form_label>
            <.input field={@form[:password_confirmation]} type="password" required />
            <.form_message field={@form[:password_confirmation]} />
          </.form_item>

          <.button id="reset-password-button" class="w-full" phx-disable-with="Salvando...">
            Redefinir senha
          </.button>
        </.form>
      <% else %>
        <div id="invalid-reset-token" class="space-y-4 text-center">
          <.header class="text-center">
            Link inválido
            <:subtitle>
              Este link de redefinição não vale mais — ele pode ter expirado ou já ter sido
              usado. Peça um novo para escolher a sua senha.
            </:subtitle>
          </.header>

          <.link navigate={~p"/password/forgot"} class={button_variant(%{variant: "outline"})}>
            Pedir um novo link
          </.link>
        </div>
      <% end %>
    </Layouts.public>
    """
  end
end
