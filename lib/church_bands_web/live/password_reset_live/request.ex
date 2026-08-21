defmodule ChurchBandsWeb.PasswordResetLive.Request do
  @moduledoc """
  Tela "Esqueci minha senha" (US 1.7) — acesso público.

  A resposta é sempre a mesma, tenha o e-mail conta ou não: dizer "esse e-mail
  não existe" entregaria a quem quisesse descobrir quais endereços fazem parte
  do grupo.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts

  @generic_message """
  Se houver uma conta ativa com esse e-mail, o link de redefinição já está a \
  caminho. Verifique também a caixa de spam.\
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Esqueci minha senha")
     |> assign(:sent?, false)
     |> assign(:generic_message, @generic_message)
     |> assign(:form, to_form(%{"email" => ""}, as: :user))}
  end

  @impl true
  def handle_event("save", %{"user" => %{"email" => email}}, socket) do
    :ok = Accounts.request_password_reset(email)

    {:noreply, assign(socket, :sent?, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm">
        <%= if @sent? do %>
          <div id="reset-requested" class="text-center space-y-4">
            <.header class="text-center">
              Verifique seu e-mail
              <:subtitle>{@generic_message}</:subtitle>
            </.header>

            <.button navigate={~p"/login"}>Voltar para o login</.button>
          </div>
        <% else %>
          <.header class="text-center">
            Esqueci minha senha
            <:subtitle>
              Informe o e-mail da sua conta e enviaremos um link para você escolher uma senha nova.
            </:subtitle>
          </.header>

          <.form for={@form} id="password-reset-request-form" phx-submit="save">
            <.input field={@form[:email]} type="email" label="E-mail" required />

            <.button
              id="request-reset-button"
              class="w-full mt-4"
              variant="primary"
              phx-disable-with="Enviando..."
            >
              Enviar link de redefinição
            </.button>
          </.form>

          <p class="mt-4 text-center text-sm text-base-content/70">
            Lembrou a senha?
            <.link navigate={~p"/login"} class="link link-hover font-semibold">Entrar</.link>
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
