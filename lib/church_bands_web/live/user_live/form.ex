defmodule ChurchBandsWeb.UserLive.Form do
  @moduledoc """
  Edição dos dados de outra pessoa (US 1.8): nome, telefone, foto e papel de
  acesso.

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_user_manager`, que também carrega `@user`): só Pastor e Líder de
  Louvor chegam aqui. Não existe botão para os demais na lista, e forçar a URL
  devolve para `/users`.

  Esta tela **não** substitui `/profile` (US 1.5): lá cada um cuida do próprio
  contato, aqui quem tem acesso total corrige o dado de outra pessoa. Por isso
  o changeset é outro (`User.management_changeset/2`) — o do próprio perfil
  precisa continuar recusando nome e papel de acesso.

  E-mail aparece só para conferência: é a credencial que veio do convite
  (US 1.1) e trocá-lo seria trocar a identidade da conta. Senha não aparece de
  jeito nenhum — quem esqueceu a sua usa a recuperação (US 1.7).

  As duas travas do papel de acesso — ninguém muda o próprio, e o sistema nunca
  fica sem acesso total — moram em `ChurchBands.Accounts.update_user/3` e
  chegam aqui como erro no campo, não como tela escondida.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.user

    {:ok,
     socket
     |> assign(:page_title, "Editar #{user.name}")
     |> assign(:self?, user.id == socket.assigns.current_user.id)
     |> assign(:role_options, role_options())
     |> assign_form(%{})}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign_form(socket, params, :validate)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    %{current_user: actor, user: user} = socket.assigns

    case Accounts.update_user(actor, user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dados de #{user.name} atualizados.")
         |> push_navigate(to: ~p"/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  defp assign_form(socket, params, action \\ nil) do
    changeset =
      Accounts.change_user_management(socket.assigns.current_user, socket.assigns.user, params)

    assign(socket, :form, to_form(changeset, action: action))
  end

  defp role_options do
    Enum.map(User.global_roles(), &{Layouts.role_label(&1), &1})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Editar {@user.name}
        <:subtitle>
          Corrija os dados de quem faz parte do grupo. O e-mail de acesso e a senha não se
          mudam por aqui.
        </:subtitle>
        <:actions>
          <.button id="back-to-users" navigate={~p"/users"}>Voltar para a lista</.button>
        </:actions>
      </.header>

      <div class="mt-6 flex items-center gap-4">
        <img
          :if={@user.photo_url}
          id="user-form-photo"
          src={@user.photo_url}
          alt={"Foto de #{@user.name}"}
          class="size-16 rounded-full object-cover ring-2 ring-base-300"
        />
        <div
          :if={is_nil(@user.photo_url)}
          id="user-form-photo-placeholder"
          class="flex size-16 items-center justify-center rounded-full bg-base-200 text-base-content/40"
        >
          <.icon name="hero-user" class="size-8" />
        </div>
        <div>
          <p class="text-sm text-base-content/60">E-mail de acesso</p>
          <p id="user-form-email" class="font-medium">{@user.email}</p>
        </div>
      </div>

      <.form for={@form} id="user-form" phx-change="validate" phx-submit="save" class="mt-6">
        <.input field={@form[:name]} type="text" label="Nome" required />

        <.input field={@form[:phone]} type="tel" label="Telefone" placeholder="(11) 99999-9999" />

        <.input
          field={@form[:photo_url]}
          type="url"
          label="Foto"
          placeholder="https://exemplo.com/foto.jpg"
        />
        <p class="mt-1 text-sm text-base-content/60">
          Endereço de uma imagem já publicada na internet. Deixe em branco para ficar sem foto.
        </p>

        <.input
          field={@form[:global_role]}
          type="select"
          label="Papel de acesso"
          options={@role_options}
          required
        />
        <p id="role-hint" class="mt-1 text-sm text-base-content/60">
          {if @self?,
            do:
              "Você não muda o seu próprio papel de acesso — promover e rebaixar é sempre decisão de outra pessoa com acesso total.",
            else:
              "Pastor(a) e Líder de Louvor têm acesso total ao sistema. Líder de Banda não é escolhido aqui: nasce de quem lidera cada banda."}
        </p>

        <div class="flex gap-2 mt-6">
          <.button variant="primary" phx-disable-with="Salvando...">Salvar alterações</.button>
          <.button id="cancel-user-form" navigate={~p"/users"}>Cancelar</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
