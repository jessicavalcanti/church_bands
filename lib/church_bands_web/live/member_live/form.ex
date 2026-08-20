defmodule ChurchBandsWeb.MemberLive.Form do
  @moduledoc """
  Integrantes de uma banda (US 1.4): adiciona um músico já existente no sistema
  ao elenco da banda, com a função que ele exerce ali.

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_band_member_manager`, que também carrega `@band`): Líder da própria
  banda, Pastor ou Líder de Louvor. A remoção reconsulta o contexto antes de
  agir — esconder o botão nunca é autorização.

  A tela lista o elenco atual junto com o formulário porque é o retorno visível
  de ter adicionado alguém. A US 1.6 leva essa lista para a página de detalhe
  da banda (`/bands/:id`), de onde esta tela passará a ser só o formulário.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember

  @instrument_suggestions [
    "Violão",
    "Guitarra",
    "Baixo",
    "Bateria",
    "Teclado",
    "Piano",
    "Percussão",
    "Saxofone",
    "Trompete",
    "Violino",
    "Flauta"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Integrantes da #{socket.assigns.band.name}")
     |> assign(:instrument_suggestions, @instrument_suggestions)
     |> reset_form()
     |> load_members()}
  end

  @impl true
  def handle_event("validate", %{"band_member" => params} = payload, socket) do
    changeset = Bands.change_member(%BandMember{}, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> search_candidates(Map.get(payload, "search", ""))}
  end

  def handle_event("select_user", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.candidates, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Músico não encontrado. Busque novamente.")}

      user ->
        {:noreply,
         socket
         |> assign_form_params(%{"user_id" => user.id})
         |> assign(:selected_user, user)
         |> search_candidates("")}
    end
  end

  def handle_event("clear_user", _params, socket) do
    {:noreply,
     socket
     |> assign_form_params(%{"user_id" => nil})
     |> assign(:selected_user, nil)
     |> search_candidates("")}
  end

  def handle_event("save", %{"band_member" => params}, socket) do
    {user_id, attrs} = Map.pop(params, "user_id")

    case Bands.add_member(socket.assigns.band, user_id, attrs) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} entrou na #{socket.assigns.band.name}.")
         |> reset_form()
         |> load_members()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    member = Bands.get_member(id)
    band = socket.assigns.band

    # Reconsulta a permissão e confere que o vínculo é mesmo desta banda: o id
    # vem do navegador e poderia apontar para o elenco de outra.
    cond do
      not Bands.manage_members?(socket.assigns.current_user, band) ->
        {:noreply, put_flash(socket, :error, "Você não tem permissão para remover integrantes.")}

      is_nil(member) or member.band_id != band.id ->
        {:noreply, socket |> put_flash(:error, "Integrante não encontrado.") |> load_members()}

      true ->
        {:ok, member} = Bands.remove_member(member)

        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} saiu da #{band.name}.")
         |> load_members()}
    end
  end

  defp reset_form(socket) do
    socket
    |> assign(:form, to_form(Bands.change_member()))
    |> assign(:selected_user, nil)
    |> assign(:search, "")
    |> assign(:candidates, [])
  end

  # Preserva o que já estava preenchido no formulário ao mexer só no músico
  # escolhido, para que a função selecionada não se perca.
  defp assign_form_params(socket, changes) do
    params =
      socket.assigns.form.params
      |> Map.merge(Map.new(changes, fn {key, value} -> {to_string(key), value} end))

    assign(socket, :form, to_form(Bands.change_member(%BandMember{}, params)))
  end

  # Enquanto houver alguém escolhido não há o que sugerir — a busca só volta a
  # rodar depois de limpar a escolha.
  defp search_candidates(socket, search) do
    candidates =
      if socket.assigns.selected_user,
        do: [],
        else: Bands.search_member_candidates(socket.assigns.band, search)

    socket
    |> assign(:search, search)
    |> assign(:candidates, candidates)
  end

  defp load_members(socket) do
    members = Bands.list_members(socket.assigns.band)

    socket
    |> assign(:members, members)
    |> assign(:members_count, length(members))
  end

  # `user_id` mora num campo escondido, que não tem onde mostrar erro. Depois de
  # uma tentativa de salvar, o recado sobe para junto do campo de músico — que
  # é onde a pessoa está olhando — tanto com a busca aberta quanto com alguém
  # já escolhido (o vínculo repetido só aparece nesse segundo caso).
  # A `action` do changeset é `:insert` apenas logo após um salvamento
  # recusado: enquanto se digita na busca ela é `:validate`, e aí não há recado
  # nenhum para dar.
  defp musician_errors(form) do
    if form.source.action == :insert do
      Enum.map(form[:user_id].errors, fn {message, _opts} -> message end)
    else
      []
    end
  end

  defp selected_type(form) do
    case form[:type].value do
      value when value in [:instrumentalist, "instrumentalist"] -> :instrumentalist
      value when value in [:vocalist, "vocalist"] -> :vocalist
      _ -> nil
    end
  end

  defp role_label(%BandMember{type: :instrumentalist} = member), do: member.instrument
  defp role_label(%BandMember{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Integrantes da {@band.name}
        <:subtitle>
          Adicione músicos com conta ativa e defina a função de cada um nesta banda.
        </:subtitle>
        <:actions>
          <.button id="back-to-bands" navigate={~p"/bands"}>Voltar para as bandas</.button>
        </:actions>
      </.header>

      <.form for={@form} id="member-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:user_id]} type="hidden" />

        <div :if={@selected_user} id="selected-user" class="fieldset mb-2">
          <span class="label mb-1">Músico</span>
          <div class="flex items-center gap-3 rounded-lg border border-base-content/20 px-3 py-2">
            <span class="font-medium">{@selected_user.name}</span>
            <span class="text-sm text-base-content/60">{@selected_user.email}</span>
            <button
              type="button"
              id="clear-user"
              phx-click="clear_user"
              class="btn btn-primary btn-soft ml-auto"
            >
              Trocar
            </button>
          </div>
        </div>

        <div :if={is_nil(@selected_user)}>
          <.input
            type="text"
            name="search"
            id="member-search"
            value={@search}
            label="Músico"
            placeholder="Busque por nome ou e-mail"
            autocomplete="off"
            phx-debounce="300"
          />

          <ul
            :if={@candidates != []}
            id="member-candidates"
            class="mb-2 divide-y divide-base-content/10 rounded-lg border border-base-content/20"
          >
            <li :for={user <- @candidates}>
              <button
                type="button"
                id={"select-user-#{user.id}"}
                phx-click="select_user"
                phx-value-id={user.id}
                class="w-full px-3 py-2 text-left transition-colors hover:bg-base-content/5"
              >
                <span class="font-medium">{user.name}</span>
                <span class="ml-2 text-sm text-base-content/60">{user.email}</span>
              </button>
            </li>
          </ul>

          <p
            :if={@candidates == [] and String.trim(@search) != ""}
            id="member-candidates-empty"
            class="mb-2 text-sm text-base-content/60"
          >
            Nenhum músico disponível com esse nome ou e-mail. Só aparecem contas já ativas
            que ainda não estão nesta banda.
          </p>
        </div>

        <p
          :for={message <- musician_errors(@form)}
          class="mb-2 flex items-center gap-2 text-sm text-error"
        >
          <.icon name="hero-exclamation-circle" class="size-5" />{message}
        </p>

        <.input
          field={@form[:type]}
          type="select"
          label="Função"
          prompt="Escolha a função"
          options={[{"Instrumentista", "instrumentalist"}, {"Vocalista", "vocalist"}]}
        />

        <.input
          :if={selected_type(@form) == :instrumentalist}
          field={@form[:instrument]}
          type="text"
          label="Instrumento"
          list="instrument-suggestions"
          autocomplete="off"
          placeholder="Guitarra, teclado, bateria..."
        />

        <datalist id="instrument-suggestions">
          <option :for={instrument <- @instrument_suggestions} value={instrument}></option>
        </datalist>

        <.input
          :if={selected_type(@form) == :vocalist}
          field={@form[:voice_part]}
          type="select"
          label="Naipe"
          prompt="Escolha o naipe"
          options={BandMember.voice_parts()}
        />

        <div class="mt-4">
          <.button variant="primary" phx-disable-with="Adicionando...">
            Adicionar à banda
          </.button>
        </div>
      </.form>

      <div class="mt-10">
        <.header>
          Elenco atual
          <:subtitle>{@members_count} integrante(s) nesta banda.</:subtitle>
        </.header>

        <div
          :if={@members_count == 0}
          id="members-empty"
          class="py-8 text-center text-base-content/60"
        >
          Nenhum músico vinculado a esta banda ainda.
        </div>

        <.table :if={@members_count > 0} id="members" rows={@members}>
          <:col :let={member} label="Músico">
            <span class="font-medium">{member.user.name}</span>
            <p class="text-sm text-base-content/60">{member.user.email}</p>
          </:col>
          <:col :let={member} label="Função">{role_label(member)}</:col>
          <:action :let={member}>
            <.button
              id={"remove-member-#{member.id}"}
              phx-click="remove"
              phx-value-id={member.id}
              data-confirm={"Remover #{member.user.name} da #{@band.name}?"}
            >
              Remover
            </.button>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end
end
