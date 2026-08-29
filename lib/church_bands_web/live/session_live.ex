defmodule ChurchBandsWeb.SessionLive do
  @moduledoc """
  Tela de login (US 1.2) — acesso público.

  O formulário faz um POST HTTP de verdade para `SessionController.create/2`,
  porque só uma requisição comum consegue gravar o cookie de sessão; a
  LiveView cuida apenas da tela e do preenchimento.
  """
  use ChurchBandsWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    if socket.assigns.current_user do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      form = to_form(%{"email" => params["email"] || "", "password" => ""}, as: :user)

      {:ok,
       socket
       |> assign(:page_title, "Entrar")
       |> assign(:form, form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <.worship_illustration />

      <.header class="text-center">
        Entrar
        <:subtitle>Use o e-mail e a senha da sua conta.</:subtitle>
      </.header>

      <.form for={@form} id="login-form" action={~p"/login"} method="post" class="space-y-4">
        <.form_item>
          <.form_label field={@form[:email]}>E-mail</.form_label>
          <.input field={@form[:email]} type="email" required />
          <.form_message field={@form[:email]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:password]}>Senha</.form_label>
          <.input field={@form[:password]} type="password" required />
          <.form_message field={@form[:password]} />
        </.form_item>

        <.button id="login-button" class="w-full" phx-disable-with="Entrando...">
          Entrar
        </.button>
      </.form>

      <p class="text-muted-foreground text-center text-sm">
        <.link
          id="forgot-password-link"
          navigate={~p"/password/forgot"}
          class="hover:text-foreground font-semibold underline underline-offset-4"
        >
          Esqueci minha senha
        </.link>
      </p>
    </Layouts.public>
    """
  end
end
