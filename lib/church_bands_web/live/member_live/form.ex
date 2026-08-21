defmodule ChurchBandsWeb.MemberLive.Form do
  @moduledoc """
  Integrantes de uma banda (US 1.4): adiciona um músico já existente no sistema
  ao elenco da banda, com a função que ele exerce ali.

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_band_member_manager`, que também carrega `@band`): Líder da própria
  banda, Pastor ou Líder de Louvor. A remoção reconsulta o contexto antes de
  agir — esconder o botão nunca é autorização.

  O campo de músico é um dropdown de quem pode entrar, com uma busca ao lado
  que apenas o estreita: a lista completa serve para escolher olhando, e a
  busca serve para quem já sabe o nome. Quem já é integrante desta banda fica
  de fora das duas; quem toca em outra banda continua disponível.

  O elenco mora na página de detalhe da banda (`/bands/:id`, US 1.6), e é para
  lá que esta tela devolve depois de vincular alguém: a lista crescendo é o
  retorno visível de ter adicionado. Remover um integrante também acontece
  lá, ao lado do nome dele.
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
     |> assign(:page_title, "Adicionar integrante à #{socket.assigns.band.name}")
     |> assign(:instrument_suggestions, @instrument_suggestions)
     |> reset_form()}
  end

  @impl true
  def handle_event("validate", %{"band_member" => params} = payload, socket) do
    changeset = Bands.change_member(%BandMember{}, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> load_candidates(Map.get(payload, "search", ""))}
  end

  def handle_event("save", %{"band_member" => params}, socket) do
    band = socket.assigns.band
    {user_id, attrs} = Map.pop(params, "user_id")

    case Bands.add_member(band, user_id, attrs) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} entrou na #{band.name}.")
         |> push_navigate(to: ~p"/bands/#{band.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp reset_form(socket) do
    socket
    |> assign(:form, to_form(Bands.change_member()))
    |> load_candidates("")
  end

  # A busca não escolhe ninguém: ela só estreita o dropdown. Quem já está
  # selecionado continua na lista mesmo que deixe de casar com o texto — senão
  # digitar depois de escolher apagaria a escolha.
  defp load_candidates(socket, search) do
    candidates = Bands.list_member_candidates(socket.assigns.band, search)
    selected = selected_user(socket, candidates)

    socket
    |> assign(:search, search)
    |> assign(:candidates, candidates)
    |> assign(:musician_options, musician_options(candidates, selected))
  end

  defp selected_user(socket, candidates) do
    case socket.assigns.form[:user_id].value do
      nil ->
        nil

      "" ->
        nil

      id ->
        id = to_string(id)

        Enum.find(candidates, fn user -> to_string(user.id) == id end) ||
          Enum.find(Bands.list_member_candidates(socket.assigns.band), fn user ->
            to_string(user.id) == id
          end)
    end
  end

  defp musician_options(candidates, selected) do
    candidates
    |> maybe_prepend(selected)
    |> Enum.map(&{"#{&1.name} — #{&1.email}", &1.id})
  end

  defp maybe_prepend(candidates, nil), do: candidates

  defp maybe_prepend(candidates, selected) do
    if Enum.any?(candidates, &(&1.id == selected.id)),
      do: candidates,
      else: [selected | candidates]
  end

  defp selected_type(form) do
    case form[:type].value do
      value when value in [:instrumentalist, "instrumentalist"] -> :instrumentalist
      value when value in [:vocalist, "vocalist"] -> :vocalist
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Adicionar integrante à {@band.name}
        <:subtitle>
          Escolha um músico com conta ativa e defina a função dele nesta banda.
        </:subtitle>
        <:actions>
          <.button id="back-to-band" navigate={~p"/bands/#{@band.id}"}>
            Voltar para a banda
          </.button>
        </:actions>
      </.header>

      <.form for={@form} id="member-form" phx-change="validate" phx-submit="save">
        <.input
          type="text"
          name="search"
          id="member-search"
          value={@search}
          label="Filtrar a lista"
          placeholder="Nome ou e-mail"
          autocomplete="off"
          phx-debounce="300"
        />

        <.input
          field={@form[:user_id]}
          type="select"
          label="Músico"
          prompt="Escolha o músico"
          options={@musician_options}
        />

        <p
          :if={@musician_options == []}
          id="no-candidates"
          class="mb-2 text-sm text-base-content/60"
        >
          {if String.trim(@search) == "",
            do: "Todo mundo com conta ativa já está nesta banda.",
            else: "Nenhum músico disponível com esse nome ou e-mail."} A lista só traz contas já ativas que ainda não são integrantes daqui — quem toca em
          outra banda continua disponível.
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
    </Layouts.app>
    """
  end
end
