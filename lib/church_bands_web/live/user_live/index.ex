defmodule ChurchBandsWeb.UserLive.Index do
  @moduledoc """
  Lista das pessoas do grupo de louvor (US 1.8).

  Leitura é ampla: qualquer usuário logado vê todo mundo, com contato, papel de
  acesso e as bandas em que cada um toca — é a resposta para "quem faz parte do
  grupo e como falo com essa pessoa", sem precisar abrir banda por banda.

  Escrita é restrita: o botão *Editar* só aparece para Pastor e Líder de Louvor,
  e a decisão real está na `live_session` de `/users/:id/edit`
  (`:ensure_user_manager`) — esconder o botão nunca é autorização.

  Convite ainda não aceito não aparece aqui: enquanto não vira conta, ele é
  acompanhado em `/admin/invites` (US 1.1).
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pessoas")
     |> assign(:can_manage?, Accounts.manage_users?(socket.assigns.current_user))
     |> load_users("")}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, load_users(socket, search)}
  end

  defp load_users(socket, search) do
    users = Accounts.list_users(search)
    bands_by_user = Bands.list_bands_by_user(Enum.map(users, & &1.id))
    people = Enum.map(users, &%{user: &1, bands: Map.get(bands_by_user, &1.id, [])})

    socket
    |> assign(:search, search)
    |> assign(:people_count, length(people))
    |> stream(:people, people, reset: true, dom_id: &"person-#{&1.user.id}")
  end

  defp role_label(%BandMember{type: :instrumentalist} = member), do: member.instrument
  defp role_label(%BandMember{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Pessoas
        <:subtitle>
          Todo mundo com conta ativa no grupo de louvor. Quem foi convidado e ainda não ativou
          a conta não aparece aqui.
        </:subtitle>
      </.header>

      <form id="user-search-form" phx-change="search" phx-submit="search" class="mt-4">
        <.input
          type="text"
          name="search"
          id="user-search"
          value={@search}
          label="Buscar pessoa"
          placeholder="Nome ou e-mail"
          autocomplete="off"
          phx-debounce="300"
        />
      </form>

      <div :if={@people_count == 0} id="users-empty" class="text-base-content/60 py-8 text-center">
        {if String.trim(@search) == "",
          do: "Ninguém ativou a conta ainda.",
          else: "Ninguém com esse nome ou e-mail."}
      </div>

      <.table :if={@people_count > 0} id="users" rows={@streams.people}>
        <:col :let={{_id, person}} label="Pessoa">
          <div class="flex items-center gap-3">
            <img
              :if={person.user.photo_url}
              id={"user-photo-#{person.user.id}"}
              src={person.user.photo_url}
              alt={"Foto de #{person.user.name}"}
              class="size-10 rounded-full object-cover ring-1 ring-base-300"
            />
            <div
              :if={is_nil(person.user.photo_url)}
              id={"user-photo-placeholder-#{person.user.id}"}
              class="flex size-10 items-center justify-center rounded-full bg-base-200 text-base-content/40"
            >
              <.icon name="hero-user" class="size-5" />
            </div>
            <div>
              <p class="font-medium">{person.user.name}</p>
              <p class="text-sm text-base-content/60">{person.user.email}</p>
            </div>
          </div>
        </:col>
        <:col :let={{_id, person}} label="Telefone">
          <span :if={person.user.phone}>{person.user.phone}</span>
          <span :if={is_nil(person.user.phone)} class="text-base-content/40 italic">
            Sem telefone
          </span>
        </:col>
        <:col :let={{_id, person}} label="Papel de acesso">
          {Layouts.role_label(person.user.global_role)}
        </:col>
        <:col :let={{_id, person}} label="Bandas">
          <span
            :if={person.bands == []}
            id={"user-bands-empty-#{person.user.id}"}
            class="text-base-content/40 italic"
          >
            Nenhuma
          </span>
          <ul :if={person.bands != []} id={"user-bands-#{person.user.id}"} class="space-y-1">
            <li :for={entry <- person.bands} class="text-sm">
              <.link navigate={~p"/bands/#{entry.band.id}"} class="link">{entry.band.name}</.link>
              <span :if={entry.leader?} class="badge badge-primary badge-sm ml-1">Líder</span>
              <span :if={entry.member} class="text-base-content/60">
                · {role_label(entry.member)}
              </span>
            </li>
          </ul>
        </:col>
        <:action :let={{_id, person}}>
          <.button
            :if={@can_manage?}
            id={"edit-user-#{person.user.id}"}
            navigate={~p"/users/#{person.user.id}/edit"}
          >
            Editar
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
