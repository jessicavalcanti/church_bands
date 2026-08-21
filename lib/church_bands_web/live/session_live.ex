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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Entrar
          <:subtitle>Use o e-mail e a senha da sua conta.</:subtitle>
        </.header>

        <.form for={@form} id="login-form" action={~p"/login"} method="post">
          <.input field={@form[:email]} type="email" label="E-mail" required />
          <.input field={@form[:password]} type="password" label="Senha" required />

          <.button
            id="login-button"
            class="w-full mt-4"
            variant="primary"
            phx-disable-with="Entrando..."
          >
            Entrar
          </.button>
        </.form>

        <p class="mt-4 text-center text-sm text-base-content/70">
          <.link
            id="forgot-password-link"
            navigate={~p"/password/forgot"}
            class="link link-hover font-semibold"
          >
            Esqueci minha senha
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end
end
