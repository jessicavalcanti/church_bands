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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={[{"Pessoas", ~p"/users"}, {@user.name, nil}]}
    >
      <:actions>
        <.link
          id="back-to-users"
          navigate={~p"/users"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar para a lista
        </.link>
      </:actions>

      <.header>
        Editar {@user.name}
        <:subtitle>
          Corrija os dados de quem faz parte do grupo. O e-mail de acesso e a senha não se
          mudam por aqui.
        </:subtitle>
      </.header>

      <div class="mt-6 flex items-center gap-4">
        <img
          :if={@user.photo_url}
          id="user-form-photo"
          src={@user.photo_url}
          alt={"Foto de #{@user.name}"}
          referrerpolicy="no-referrer"
          class="ring-border size-16 rounded-full object-cover ring-2"
        />
        <div
          :if={is_nil(@user.photo_url)}
          id="user-form-photo-placeholder"
          class="bg-muted text-muted-foreground flex size-16 items-center justify-center rounded-full"
        >
          <.icon name="hero-user" class="size-8" />
        </div>
        <div>
          <p class="text-muted-foreground text-sm">E-mail de acesso</p>
          <p id="user-form-email" class="font-medium">{@user.email}</p>
        </div>
      </div>

      <.form
        for={@form}
        id="user-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.form_item>
          <.form_label field={@form[:name]}>Nome</.form_label>
          <.input field={@form[:name]} type="text" required />
          <.form_message field={@form[:name]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:phone]}>Telefone</.form_label>
          <.input field={@form[:phone]} type="tel" placeholder="(11) 99999-9999" />
          <.form_message field={@form[:phone]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:photo_url]}>Foto</.form_label>
          <.input field={@form[:photo_url]} type="url" placeholder="https://exemplo.com/foto.jpg" />
          <.form_description>
            Endereço de uma imagem já publicada na internet. Deixe em branco para ficar sem foto.
          </.form_description>
          <.form_message field={@form[:photo_url]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:global_role]}>Papel de acesso</.form_label>
          <.select field={@form[:global_role]} options={@role_options} required />
          <.form_description id="role-hint">
            {if @self?,
              do:
                "Você não muda o seu próprio papel de acesso — promover e rebaixar é sempre decisão de outra pessoa com acesso total.",
              else:
                "Pastor(a) e Líder de Louvor têm acesso total ao sistema. Líder de Banda não é escolhido aqui: nasce de quem lidera cada banda."}
          </.form_description>
          <.form_message field={@form[:global_role]} />
        </.form_item>

        <div class="flex gap-2 pt-2">
          <.button phx-disable-with="Salvando...">Salvar alterações</.button>
          <.link
            id="cancel-user-form"
            navigate={~p"/users"}
            class={button_variant(%{variant: "outline"})}
          >
            Cancelar
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
