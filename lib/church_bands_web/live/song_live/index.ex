defmodule ChurchBandsWeb.SongLive.Index do
  @moduledoc """
  Catálogo central de músicas (US 2.1) — a lista de tudo que o grupo canta, de
  onde as bandas montarão seus repertórios.

  Nesta história a tela inteira é de acesso total: quem chega aqui já passou
  pelo `:ensure_full_access` da `live_session`, e por isso o `handle_event` de
  exclusão **não** reconsulta a permissão — o ramo de recusa não teria como ser
  alcançado. Ele nasce na US 2.5, quando `/songs` abre para leitura ampla e
  passa a receber quem não pode escrever.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Músicas")
     |> load_songs()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    song = Repertoire.get_song(id)

    # A lista inteira está velha, e não uma linha só: quem sumiu do banco ainda
    # está na tela, e provavelmente não é a única diferença.
    if is_nil(song) do
      {:noreply, socket |> put_flash(:error, "Música não encontrada.") |> load_songs()}
    else
      {:ok, song} = Repertoire.delete_song(song)

      {:noreply,
       socket
       |> put_flash(:info, "Música #{song.title} excluída.")
       |> assign(:songs_count, socket.assigns.songs_count - 1)
       |> stream_delete(:songs, song)}
    end
  end

  defp load_songs(socket) do
    songs = Repertoire.list_songs()

    socket
    |> assign(:songs_count, length(songs))
    |> stream(:songs, songs, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={[{"Músicas", nil}]}
    >
      <:actions>
        <.link id="new-song-button" navigate={~p"/songs/new"} class={button_variant(%{size: "sm"})}>
          <.icon name="hero-plus" class="mr-2 size-4" /> Nova música
        </.link>
      </:actions>

      <.header>
        Músicas
        <:subtitle>
          O catálogo do grupo. É daqui que cada banda monta o repertório dela.
        </:subtitle>
      </.header>

      <div :if={@songs_count == 0} id="songs-empty" class="text-muted-foreground py-8 text-center">
        Nenhuma música cadastrada ainda.
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
        </:col>
        <:col :let={{_id, song}} label="Artista">{song.artist}</:col>
        <:col :let={{_id, song}} label="BPM">{song.bpm}</:col>
        <:action :let={{_id, song}}>
          <.link
            id={"edit-song-#{song.id}"}
            navigate={~p"/songs/#{song.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, song}}>
          <.button
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
