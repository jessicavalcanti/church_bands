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

  defp role_label(%BandMember{type: :instrumentalist} = member), do: member.instrument
  defp role_label(%BandMember{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Meu perfil
        <:subtitle>
          Seu nome e seus dados de contato ficam com você. Papel de acesso, função e banda são
          definidos por quem lidera.
        </:subtitle>
      </.header>

      <div class="mt-6 flex items-center gap-4">
        <img
          :if={@current_user.photo_url}
          id="profile-photo"
          src={@current_user.photo_url}
          alt={"Foto de #{@current_user.name}"}
          class="size-16 rounded-full object-cover ring-2 ring-base-300"
        />
        <div
          :if={is_nil(@current_user.photo_url)}
          id="profile-photo-placeholder"
          class="flex size-16 items-center justify-center rounded-full bg-base-200 text-base-content/40"
        >
          <.icon name="hero-user" class="size-8" />
        </div>
        <div>
          <p class="font-medium">{@current_user.name}</p>
          <p class="text-sm text-base-content/60">{@current_user.email}</p>
        </div>
      </div>

      <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save" class="mt-6">
        <.input field={@form[:name]} type="text" label="Nome" required />

        <.input
          field={@form[:phone]}
          type="tel"
          label="Telefone"
          placeholder="(11) 99999-9999"
        />

        <.input
          field={@form[:photo_url]}
          type="url"
          label="Foto"
          placeholder="https://exemplo.com/minha-foto.jpg"
        />
        <p class="mt-1 text-sm text-base-content/60">
          Endereço de uma imagem já publicada na internet. Deixe em branco para ficar sem foto.
        </p>

        <div class="mt-4">
          <.button variant="primary" phx-disable-with="Salvando...">Salvar alterações</.button>
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

        <dl id="structural-fields" class="mt-4 divide-y divide-base-300 text-sm">
          <div class="flex justify-between gap-4 py-3">
            <dt class="text-base-content/60">E-mail de acesso</dt>
            <dd class="font-medium">{@current_user.email}</dd>
          </div>
          <div class="flex justify-between gap-4 py-3">
            <dt class="text-base-content/60">Papel de acesso</dt>
            <dd class="font-medium">{Layouts.role_label(@current_user.global_role)}</dd>
          </div>
        </dl>

        <div id="my-bands" class="mt-6">
          <p class="mb-2 text-sm font-medium">Minhas bandas</p>

          <p :if={@bands == []} id="my-bands-empty" class="text-sm text-base-content/60">
            Você ainda não faz parte de nenhuma banda.
          </p>

          <ul :if={@bands != []} class="divide-y divide-base-300 text-sm">
            <li :for={entry <- @bands} class="flex justify-between gap-4 py-3">
              <span>
                {entry.band.name}
                <span :if={entry.leader?} class="badge badge-primary badge-sm ml-2">Líder</span>
              </span>
              <span :if={entry.member} class="font-medium">{role_label(entry.member)}</span>
              <span :if={is_nil(entry.member)} class="text-base-content/60 italic">
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
