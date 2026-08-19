defmodule ChurchBandsWeb.DevSessionHTML do
  @moduledoc """
  Template do login de atalho de desenvolvimento. Ver
  `ChurchBandsWeb.DevSessionController`.
  """
  use ChurchBandsWeb, :html

  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Entrar como (desenvolvimento)
        <:subtitle>
          Atalho temporário até a tela de login da US 1.2. Escolha um usuário para entrar.
        </:subtitle>
      </.header>

      <ul id="dev-users" class="mt-6 space-y-2">
        <li :for={user <- @users} class="flex items-center justify-between gap-4 border-b py-2">
          <div>
            <p class="font-semibold">{user.name}</p>
            <p class="text-sm opacity-70">{user.email} — {role_label(user.global_role)}</p>
          </div>
          <.button href={~p"/dev/login/#{user.id}"} variant="primary">Entrar</.button>
        </li>
      </ul>

      <p :if={@users == []} class="mt-6 opacity-70">
        Nenhum usuário cadastrado. Rode <code>mix run priv/repo/seeds.exs</code>.
      </p>
    </Layouts.app>
    """
  end

  defp role_label(:pastor), do: "Pastor"
  defp role_label(:worship_leader), do: "Líder de Louvor"
  defp role_label(:member), do: "Músico / Técnico"
end
