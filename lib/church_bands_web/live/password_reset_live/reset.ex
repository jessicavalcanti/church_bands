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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm">
        <%= if @reset_token do %>
          <.header class="text-center">
            Redefinir senha
            <:subtitle>
              Escolha a nova senha da conta <span class="font-semibold">{@reset_token.user.email}</span>.
            </:subtitle>
          </.header>

          <.form for={@form} id="password-reset-form" phx-change="validate" phx-submit="save">
            <.input
              field={@form[:password]}
              type="password"
              label="Nova senha"
              placeholder="Ao menos 8 caracteres, com letras e números"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirme a nova senha"
              required
            />

            <.button
              id="reset-password-button"
              class="w-full mt-4"
              variant="primary"
              phx-disable-with="Salvando..."
            >
              Redefinir senha
            </.button>
          </.form>
        <% else %>
          <div id="invalid-reset-token" class="text-center space-y-4">
            <.header class="text-center">
              Link inválido
              <:subtitle>
                Este link de redefinição não vale mais — ele pode ter expirado ou já ter sido
                usado. Peça um novo para escolher a sua senha.
              </:subtitle>
            </.header>

            <.button navigate={~p"/password/forgot"}>Pedir um novo link</.button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
