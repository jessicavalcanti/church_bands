defmodule ChurchBandsWeb.SongLive.Index do
  @moduledoc """
  Catálogo central de músicas — a lista de tudo que o grupo canta, de onde as
  bandas montarão seus repertórios.

  **Ler é de qualquer um logado (US 2.5); escrever continua sendo de Pastor e
  Líder de Louvor.** A tela nasceu inteira restrita na US 2.1, e abriu aqui:
  quem toca precisa achar a cifra de uma música sem depender de quem a
  cadastrou. Os botões de cadastrar, editar, excluir e *Gerenciar tags* passam
  a ter `:if` de permissão — e é por isso que a reconferência do servidor entra
  agora, e não antes: só nesta história a recusa tem os dois lados testáveis.

  `handle_event("delete", ...)` **reconsulta `manage_songs?/1`** antes de
  apagar, na mesma estrutura de `BandLive.Index`. Esconder o botão na tela
  nunca foi autorização: o evento chega pelo socket, e quem sabe disso o
  dispara sem botão nenhum.

  A coluna **Bandas** (US 2.2) diz em quantas a música está, e sai de uma
  contagem na própria consulta do catálogo — não de uma pergunta por linha.
  Ela é a leitura de fora do que a trava de exclusão logo abaixo diz por
  dentro: música que alguma banda toca não sai daqui, e a recusa **nomeia** as
  bandas, porque o caminho de quem quer excluí-la é tirá-la do repertório
  delas (US 2.4). Quem decide quantos nomes cabem na frase é esta tela, e não o
  contexto.

  **Busca e filtro moram na URL**, não no socket. É `handle_params/3` que
  carrega a lista — o `mount/3` não filtra —, e cada mudança é um `push_patch`.
  Assim o botão voltar do navegador desfaz o filtro em vez de sair da tela, e o
  resultado de uma busca é um endereço que se manda para alguém.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Músicas")
     |> assign(:can_manage?, Repertoire.manage_songs?(socket.assigns.current_user))
     |> assign(:tags, Repertoire.list_tags())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # A tag da URL é texto que alguém pode ter escrito: `get_tag/1` devolve
    # `nil` para o que não é id e para o id que não existe, e a tela mostra o
    # catálogo inteiro. URL torta não vira lista vazia inexplicável.
    tag = Repertoire.get_tag(params["tag"] || "")
    search = params["busca"] || ""

    {:noreply, load_songs(socket, search, tag)}
  end

  @impl true
  def handle_event("search", %{"busca" => search}, socket) do
    {:noreply, push_patch(socket, to: catalog_path(search, socket.assigns.selected_tag))}
  end

  # Clicar na tag selecionada limpa o filtro: é o mesmo gesto de ida e volta
  # dos badges do formulário de música (US 2.7).
  def handle_event("filter_tag", %{"id" => id}, socket) do
    selected = socket.assigns.selected_tag
    tag = Enum.find(socket.assigns.tags, &(to_string(&1.id) == id))

    tag = if selected && tag && selected.id == tag.id, do: nil, else: tag

    {:noreply, push_patch(socket, to: catalog_path(socket.assigns.search, tag))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: catalog_path("", nil))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    song = Repertoire.get_song(id)

    # Reconsulta a permissão: esconder o botão na tela não é autorização.
    cond do
      not Repertoire.manage_songs?(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Você não tem permissão para excluir músicas.")}

      # A lista inteira está velha, e não uma linha só: quem sumiu do banco
      # ainda está na tela, e provavelmente não é a única diferença.
      is_nil(song) ->
        {:noreply, socket |> put_flash(:error, "Música não encontrada.") |> reload_songs()}

      true ->
        delete_song(socket, song)
    end
  end

  defp delete_song(socket, song) do
    case Repertoire.delete_song(song) do
      {:ok, song} ->
        {:noreply,
         socket
         |> put_flash(:info, "Música #{song.title} excluída.")
         |> assign(:songs_count, socket.assigns.songs_count - 1)
         |> stream_delete(:songs, song)}

      # A música que alguma banda toca não sai do catálogo (US 2.2): quem quer
      # excluí-la precisa antes tirá-la do repertório dessas bandas (US 2.4), e
      # para isso precisa saber quais são. Daí os nomes, e não a contagem.
      {:error, {:in_use, bands}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{song.title} está no repertório de #{bands_label(bands)}. " <>
             "Remova a música do repertório dessas bandas antes de excluí-la."
         )}
    end
  end

  # Três nomes e o resto resumido. A lista inteira caberia num flash com duas
  # bandas e viraria um parágrafo com dez — e o que quem lê precisa saber é por
  # onde começar, não a lista completa.
  @named_bands 3

  defp bands_label(bands) do
    case Enum.split(bands, @named_bands) do
      {named, []} -> to_sentence(named)
      {named, rest} -> "#{Enum.join(named, ", ")} e mais #{length(rest)}"
    end
  end

  defp to_sentence([name]), do: name

  defp to_sentence(names) do
    {first, [last]} = Enum.split(names, length(names) - 1)
    "#{Enum.join(first, ", ")} e #{last}"
  end

  defp band_count_label(0), do: "Nenhuma banda"
  defp band_count_label(1), do: "1 banda"
  defp band_count_label(count), do: "#{count} bandas"

  defp load_songs(socket, search, tag) do
    filters = %{search: search, tag_id: tag && tag.id}
    songs = Repertoire.list_songs(filters)

    socket
    |> assign(:search, search)
    |> assign(:selected_tag, tag)
    |> assign(:filtering?, Repertoire.filtering?(filters))
    |> assign(:songs_count, length(songs))
    |> stream(:songs, songs, reset: true)
  end

  defp reload_songs(socket) do
    load_songs(socket, socket.assigns.search, socket.assigns.selected_tag)
  end

  # O que não estreita nada fica fora da URL: `/songs` limpo é o endereço do
  # catálogo inteiro, e não `/songs?busca=&tag=`.
  defp catalog_path(search, tag) do
    params =
      [busca: String.trim(to_string(search)), tag: tag && tag.id]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    ~p"/songs?#{params}"
  end

  defp tag_variant(selected, tag) do
    if selected && selected.id == tag.id, do: "default", else: "outline"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[{"Músicas", nil}]}
    >
      <:actions>
        <.link
          :if={@can_manage?}
          id="manage-tags-button"
          navigate={~p"/admin/tags"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          <.icon name="hero-tag" class="mr-2 size-4" /> Gerenciar tags
        </.link>
        <.link
          :if={@can_manage?}
          id="new-song-button"
          navigate={~p"/songs/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Nova música
        </.link>
      </:actions>

      <.header>
        Músicas
        <:subtitle>
          O catálogo do grupo. É daqui que cada banda monta o repertório dela.
        </:subtitle>
      </.header>

      <form id="song-search-form" phx-change="search" phx-submit="search" class="mt-4">
        <.form_item>
          <.form_label for="song-search">Buscar música</.form_label>
          <.input
            type="text"
            name="busca"
            id="song-search"
            value={@search}
            placeholder="Título ou artista"
            autocomplete="off"
            phx-debounce="300"
          />
        </.form_item>
      </form>

      <div :if={@tags != []} id="tag-filter" class="mt-3 flex flex-wrap gap-2">
        <button
          :for={tag <- @tags}
          type="button"
          id={"filter-tag-#{tag.id}"}
          phx-click="filter_tag"
          phx-value-id={tag.id}
          aria-pressed={to_string(@selected_tag != nil and @selected_tag.id == tag.id)}
          class="focus-visible:ring-ring/50 rounded-full focus:outline-hidden focus-visible:ring-[3px]"
        >
          <.badge variant={tag_variant(@selected_tag, tag)}>{tag.name}</.badge>
        </button>
      </div>

      <div
        :if={@songs_count == 0 and not @filtering?}
        id="songs-empty"
        class="text-muted-foreground py-8 text-center"
      >
        Nenhuma música cadastrada ainda.
      </div>

      <div
        :if={@songs_count == 0 and @filtering?}
        id="songs-not-found"
        class="text-muted-foreground py-8 text-center"
      >
        <p>Nenhuma música encontrada.</p>
        <.button id="clear-filters" variant="outline" size="sm" class="mt-3" phx-click="clear_filters">
          Limpar busca e filtro
        </.button>
      </div>

      <.table :if={@songs_count > 0} id="songs" rows={@streams.songs}>
        <:col :let={{_id, song}} label="Música">
          <div class="flex items-center gap-2">
            <span class="font-medium">{song.title}</span>
            <.link
              :if={song.reference_url}
              id={"song-reference-#{song.id}"}
              href={song.reference_url}
              target="_blank"
              rel="noopener"
              aria-label={"Referência de #{song.title}"}
              class="text-muted-foreground hover:text-foreground"
            >
              <.icon name="hero-play-circle" class="size-4" />
            </.link>
            <.link
              :if={song.chord_chart_url}
              id={"song-chord-chart-#{song.id}"}
              href={song.chord_chart_url}
              target="_blank"
              rel="noopener"
              aria-label={"Cifra de #{song.title}"}
              class="text-muted-foreground hover:text-foreground"
            >
              <.icon name="hero-document-text" class="size-4" />
            </.link>
          </div>

          <div :if={song.tags != []} id={"song-tags-#{song.id}"} class="mt-1 flex flex-wrap gap-1">
            <.badge :for={tag <- song.tags} variant="secondary">{tag.name}</.badge>
          </div>
        </:col>
        <:col :let={{_id, song}} label="Artista">{song.artist}</:col>
        <:col :let={{_id, song}} label="BPM">{song.bpm}</:col>
        <:col :let={{_id, song}} label="Bandas">
          <span id={"song-band-count-#{song.id}"} class="text-muted-foreground text-sm">
            {band_count_label(song.band_count)}
          </span>
        </:col>
        <:action :let={{_id, song}}>
          <.link
            :if={@can_manage?}
            id={"edit-song-#{song.id}"}
            navigate={~p"/songs/#{song.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, song}}>
          <.button
            :if={@can_manage?}
            id={"delete-song-#{song.id}"}
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={song.id}
            data-confirm={"Excluir a música #{song.title}?"}
          >
            Excluir
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
