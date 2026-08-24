defmodule ChurchBandsWeb.BandRepertoireLive.Show do
  @moduledoc """
  O repertório de uma banda: as músicas que ela toca, cada uma no tom dela e com
  o preparo em que está.

  **Ler é de qualquer um logado (US 2.6); montar continua sendo de quem responde
  pela banda.** A tela nasceu inteira restrita na US 2.2, e abriu aqui pelo mesmo
  motivo do catálogo: quem toca precisa chegar à cifra no tom certo antes do
  ensaio, sem depender de quem monta a lista. O botão *Adicionar música* ganhou
  `:if` de `Bands.manage_repertoire?/2`, e quem forçar `/…/repertoire/new` é
  recusado pelo hook da rota — esconder o botão nunca foi autorização.

  **Não há evento de escrita nesta tela, e por isso não há reconferência de
  permissão a escrever.** Ela entra com os eventos que a exigem: mudar tom e
  status (US 2.3) e remover do repertório (US 2.4). Escrevê-la agora seria um
  ramo que nenhum teste alcança.

  A banda é carregada aqui, e não pelo hook: a rota saiu da `live_session` de
  quem gerencia, e `/bands` com <q>Banda não encontrada.</q> passou a ser
  responsabilidade do mount, como em `BandLive.Show`.

  **Busca e filtro moram na URL**, não no socket, como em `/songs`: é
  `handle_params/3` que carrega a lista, e cada mudança é um `push_patch`. Assim
  o botão voltar do navegador desfaz o filtro em vez de sair da tela, e o
  repertório filtrado é um endereço que se manda para alguém.

  **O status desconhecido na URL é ignorado**, e a tela volta ao padrão: quem lê
  o parâmetro é `parse_status/1`, casando sobre os valores aceitos. Nada de
  `String.to_existing_atom/1` sobre o que veio da barra de endereço.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.BandRepertoire

  # Os quatro badges da barra, na ordem em que uma música anda: entra em
  # aprendizado, fica pronta, é arquivada — e *Todas* por último, porque não é
  # um estado, é abrir mão do recorte.
  @status_filters [
    {:learning, "Em aprendizado"},
    {:ready, "Pronta"},
    {:archived, "Arquivada"},
    {:all, "Todas"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Bands.get_band(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Banda não encontrada.")
         |> redirect(to: ~p"/bands")}

      band ->
        {:ok,
         socket
         |> assign(:page_title, "Repertório da #{band.name}")
         |> assign(:band, band)
         |> assign(:status_filters, @status_filters)
         |> assign(
           :can_manage?,
           Bands.manage_repertoire?(socket.assigns.current_user, band)
         )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_repertoire(socket, params["busca"] || "", parse_status(params["status"]))}
  end

  @impl true
  def handle_event("search", %{"busca" => search}, socket) do
    {:noreply, push_patch(socket, to: repertoire_path(socket, search, socket.assigns.status))}
  end

  # Clicar no badge marcado limpa o filtro: é o mesmo gesto de ida e volta das
  # tags do catálogo (US 2.5).
  def handle_event("filter_status", %{"status" => status}, socket) do
    status = parse_status(status)
    status = if status == socket.assigns.status, do: nil, else: status

    {:noreply, push_patch(socket, to: repertoire_path(socket, socket.assigns.search, status))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: repertoire_path(socket, "", nil))}
  end

  defp load_repertoire(socket, search, status) do
    filters = %{search: search, status: status}
    entries = Repertoire.list_band_repertoire(socket.assigns.band, filters)

    socket
    |> assign(:search, search)
    |> assign(:status, status)
    |> assign(:filtering?, Repertoire.filtering_repertoire?(filters))
    |> assign(:entries, entries)
    |> assign(:entries_count, length(entries))
  end

  # O que vem da barra de endereço é texto que alguém pode ter escrito: só os
  # quatro valores conhecidos viram filtro, e o resto vira o padrão da tela.
  defp parse_status("learning"), do: :learning
  defp parse_status("ready"), do: :ready
  defp parse_status("archived"), do: :archived
  defp parse_status("all"), do: :all
  defp parse_status(_other), do: nil

  # O que não estreita nada fica fora da URL: o endereço do repertório inteiro é
  # `/bands/1/repertoire` limpo, e não `?busca=&status=`.
  defp repertoire_path(socket, search, status) do
    params =
      [busca: String.trim(to_string(search)), status: status && to_string(status)]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    ~p"/bands/#{socket.assigns.band.id}/repertoire?#{params}"
  end

  defp status_variant(selected, status) do
    if selected == status, do: "default", else: "outline"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={[
        {"Bandas", ~p"/bands"},
        {@band.name, ~p"/bands/#{@band.id}"},
        {"Repertório", nil}
      ]}
    >
      <:actions>
        <.link
          id="back-to-band"
          navigate={~p"/bands/#{@band.id}"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar para a banda
        </.link>
        <.link
          :if={@can_manage?}
          id="add-repertoire-song"
          navigate={~p"/bands/#{@band.id}/repertoire/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Adicionar música
        </.link>
      </:actions>

      <.header>
        Repertório da {@band.name}
        <:subtitle>
          As músicas desta banda, cada uma no tom em que ela toca.
        </:subtitle>
      </.header>

      <form id="repertoire-search-form" phx-change="search" phx-submit="search" class="mt-4">
        <.form_item>
          <.form_label for="repertoire-search">Buscar no repertório</.form_label>
          <.input
            type="text"
            name="busca"
            id="repertoire-search"
            value={@search}
            placeholder="Título ou artista"
            autocomplete="off"
            phx-debounce="300"
          />
        </.form_item>
      </form>

      <div id="status-filter" class="mt-3 flex flex-wrap gap-2">
        <button
          :for={{status, label} <- @status_filters}
          type="button"
          id={"filter-status-#{status}"}
          phx-click="filter_status"
          phx-value-status={status}
          aria-pressed={to_string(@status == status)}
          class="focus-visible:ring-ring/50 rounded-full focus:outline-hidden focus-visible:ring-[3px]"
        >
          <.badge variant={status_variant(@status, status)}>{label}</.badge>
        </button>
      </div>

      <div
        :if={@entries_count == 0 and not @filtering?}
        id="repertoire-empty"
        class="text-muted-foreground py-8 text-center"
      >
        <p>Nenhuma música no repertório ainda.</p>
        <p :if={@can_manage?} class="mt-1">
          Use <strong>Adicionar música</strong> para escolher a primeira do catálogo e o tom
          desta banda.
        </p>
        <p :if={not @can_manage?} class="mt-1">
          Quem monta o repertório é o Líder desta banda, o Pastor ou o Líder de Louvor.
        </p>
      </div>

      <div
        :if={@entries_count == 0 and @filtering?}
        id="repertoire-not-found"
        class="text-muted-foreground py-8 text-center"
      >
        <p>Nenhuma música encontrada.</p>
        <.button id="clear-filters" variant="outline" size="sm" class="mt-3" phx-click="clear_filters">
          Limpar busca e filtro
        </.button>
      </div>

      <.table :if={@entries_count > 0} id="repertoire" rows={@entries}>
        <:col :let={entry} label="Música">
          <div class="flex items-center gap-2">
            <span class="font-medium">{entry.song.title}</span>
            <.link
              :if={entry.song.reference_url}
              id={"repertoire-reference-#{entry.id}"}
              href={entry.song.reference_url}
              target="_blank"
              rel="noopener"
              aria-label={"Referência de #{entry.song.title}"}
              class="text-muted-foreground hover:text-foreground"
            >
              <.icon name="hero-play-circle" class="size-4" />
            </.link>
            <.link
              :if={entry.song.chord_chart_url}
              id={"repertoire-chord-chart-#{entry.id}"}
              href={entry.song.chord_chart_url}
              target="_blank"
              rel="noopener"
              aria-label={"Cifra de #{entry.song.title}"}
              class="text-muted-foreground hover:text-foreground"
            >
              <.icon name="hero-document-text" class="size-4" />
            </.link>
          </div>

          <div
            :if={entry.song.tags != []}
            id={"repertoire-tags-#{entry.id}"}
            class="mt-1 flex flex-wrap gap-1"
          >
            <.badge :for={tag <- entry.song.tags} variant="secondary">{tag.name}</.badge>
          </div>
        </:col>
        <:col :let={entry} label="Artista">{entry.song.artist}</:col>
        <:col :let={entry} label="Tom">
          <span id={"repertoire-key-#{entry.id}"} class="font-medium">{entry.key}</span>
        </:col>
        <:col :let={entry} label="Status">
          <.badge id={"repertoire-status-#{entry.id}"} variant="secondary">
            {BandRepertoire.status_label(entry.status)}
          </.badge>
        </:col>
      </.table>
    </Layouts.app>
    """
  end
end
