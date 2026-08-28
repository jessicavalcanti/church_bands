defmodule ChurchBandsWeb.ProfileLive do
  @moduledoc """
  Edição do próprio perfil (US 1.5).

  Qualquer usuário logado edita aqui os próprios dados — nome, telefone e
  foto — independentemente do papel. A autorização acontece na `live_session`
  do router (`:ensure_authenticated`), e o alvo da edição é sempre
  `current_user`: a tela não recebe id, então não existe URL para editar o
  perfil de outra pessoa.

  O nome fica no formulário junto com o contato: quem o digitou foi a própria
  pessoa, no formulário de ativação de conta, e um erro de digitação ali não
  pode virar um nome errado para sempre.

  O resto da página é somente leitura, e é assim de propósito. E-mail, papel de
  acesso e as funções em cada banda não são dados de contato: o e-mail é a
  credencial que veio do convite, e os outros dois mudam pela mão de quem
  lidera — na lista de pessoas (US 1.8) e nas telas de banda e de integrantes.
  Aqui eles aparecem para conferência, sem campo de formulário — e
  `User.profile_changeset/2` também os ignora, para que forjar o parâmetro no
  navegador não os altere.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Meu perfil")
     |> assign(:bands, Bands.list_user_bands(user))
     |> assign_user(user)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_profile(socket.assigns.current_user, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_profile(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Perfil atualizado.")
         |> assign_user(user)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # Depois de salvar, o usuário atualizado precisa valer também para o resto da
  # tela — a barra do topo e os dados somente leitura leem `current_user`.
  defp assign_user(socket, user) do
    socket
    |> assign(:current_user, user)
    |> assign(:form, to_form(Accounts.change_profile(user)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={[{"Meu perfil", nil}]}
    >
      <.header>
        Meu perfil
        <:subtitle>
          Seu nome e seus dados de contato ficam com você. Papel de acesso, função e banda são
          definidos por quem lidera.
        </:subtitle>
      </.header>

      <div class="mt-6 flex items-center gap-4">
        <.user_photo id="profile-photo" user={@current_user} />
        <div>
          <p class="font-medium">{@current_user.name}</p>
          <p class="text-muted-foreground text-sm">{@current_user.email}</p>
        </div>
      </div>

      <.form
        for={@form}
        id="profile-form"
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
          <.input
            field={@form[:photo_url]}
            type="url"
            placeholder="https://exemplo.com/minha-foto.jpg"
          />
          <.form_description>
            Endereço de uma imagem já publicada na internet. Deixe em branco para ficar sem foto.
          </.form_description>
          <.form_message field={@form[:photo_url]} />
        </.form_item>

        <div class="pt-2">
          <.button phx-disable-with="Salvando...">Salvar alterações</.button>
        </div>
      </.form>

      <div class="mt-10">
        <.header>
          Dados definidos pela liderança
          <:subtitle>
            Somente leitura. Para corrigir algo aqui, fale com o Líder da sua banda, o Pastor
            ou o Líder de Louvor.
          </:subtitle>
        </.header>

        <dl id="structural-fields" class="divide-border mt-4 divide-y text-sm">
          <div class="flex justify-between gap-4 py-3">
            <dt class="text-muted-foreground">E-mail de acesso</dt>
            <dd class="font-medium">{@current_user.email}</dd>
          </div>
          <div class="flex justify-between gap-4 py-3">
            <dt class="text-muted-foreground">Papel de acesso</dt>
            <dd class="font-medium">{User.role_label(@current_user.global_role)}</dd>
          </div>
        </dl>

        <div id="my-bands" class="mt-6">
          <p class="mb-2 text-sm font-medium">Minhas bandas</p>

          <p :if={@bands == []} id="my-bands-empty" class="text-muted-foreground text-sm">
            Você ainda não faz parte de nenhuma banda.
          </p>

          <ul :if={@bands != []} class="divide-border divide-y text-sm">
            <li :for={entry <- @bands} class="flex justify-between gap-4 py-3">
              <span>
                {entry.band.name}
                <.badge :if={entry.leader?} class="ml-2">Líder</.badge>
              </span>
              <span :if={entry.member} class="font-medium">{BandMember.role_label(entry.member)}</span>
              <span :if={is_nil(entry.member)} class="text-muted-foreground italic">
                Sem função definida
              </span>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
