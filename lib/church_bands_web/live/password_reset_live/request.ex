defmodule ChurchBandsWeb.PasswordResetLive.Request do
  @moduledoc """
  Tela "Esqueci minha senha" (US 1.7) — acesso público.

  A resposta é sempre a mesma, tenha o e-mail conta ou não: dizer "esse e-mail
  não existe" entregaria a quem quisesse descobrir quais endereços fazem parte
  do grupo.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.RateLimit

  @too_many_attempts """
  Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.\
  """

  @generic_message """
  Se houver uma conta ativa com esse e-mail, o link de redefinição já está a \
  caminho. Verifique também a caixa de spam.\
  """

  @impl true
  def mount(_params, _session, socket) do
    %{address: address} = get_connect_info(socket, :peer_data)

    {:ok,
     socket
     |> assign(:page_title, "Esqueci minha senha")
     |> assign(:sent?, false)
     |> assign(:client_ip, address)
     |> assign(:generic_message, @generic_message)
     |> assign(:form, to_form(%{"email" => ""}, as: :user))}
  end

  @impl true
  def handle_event("save", %{"user" => %{"email" => email}}, socket) when is_binary(email) do
    # Sem limite, esta tela é um botão de mandar e-mail para qualquer endereço,
    # de graça e quantas vezes se quiser. O IP vem do socket, e não do
    # formulário, porque é a única parte do pedido que quem pede não escolhe.
    case RateLimit.hit(:password_reset,
           ip: socket.assigns.client_ip,
           email: Accounts.normalize_email(email)
         ) do
      :ok ->
        :ok = Accounts.request_password_reset(email)
        {:noreply, assign(socket, :sent?, true)}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, @too_many_attempts)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <%= if @sent? do %>
        <div id="reset-requested" class="space-y-4 text-center">
          <.header class="text-center">
            Verifique seu e-mail
            <:subtitle>{@generic_message}</:subtitle>
          </.header>

          <.link navigate={~p"/login"} class={button_variant(%{variant: "outline"})}>
            Voltar para o login
          </.link>
        </div>
      <% else %>
        <.header class="text-center">
          Esqueci minha senha
          <:subtitle>
            Informe o e-mail da sua conta e enviaremos um link para você escolher uma senha nova.
          </:subtitle>
        </.header>

        <.form for={@form} id="password-reset-request-form" phx-submit="save" class="space-y-4">
          <.form_item>
            <.form_label field={@form[:email]}>E-mail</.form_label>
            <.input field={@form[:email]} type="email" required />
            <.form_message field={@form[:email]} />
          </.form_item>

          <.button id="request-reset-button" class="w-full" phx-disable-with="Enviando...">
            Enviar link de redefinição
          </.button>
        </.form>

        <p class="text-muted-foreground text-center text-sm">
          Lembrou a senha?
          <.link
            navigate={~p"/login"}
            class="hover:text-foreground font-semibold underline underline-offset-4"
          >
            Entrar
          </.link>
        </p>
      <% end %>
    </Layouts.public>
    """
  end
end
