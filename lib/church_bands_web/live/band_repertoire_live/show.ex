defmodule ChurchBandsWeb.BandRepertoireLive.Show do
  @moduledoc """
  O repertório de uma banda (US 2.2): as músicas que ela toca, cada uma no tom
  dela e com o preparo em que está.

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_band_repertoire_manager`, que também carrega `@band`): Líder da
  própria banda, Pastor ou Líder de Louvor.

  **Nesta história a tela é de quem monta.** Músico comum ainda não entra, nem
  para olhar — é a US 2.6 que abre a leitura, e ela é que vai trazer as tags das
  músicas e o filtro por status para cá. Mudar tom e status (US 2.3) e remover
  do repertório (US 2.4) também chegam depois; por enquanto o que se faz aqui é
  ver a lista e ir para o formulário de vínculo.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.BandRepertoire

  @impl true
  def mount(_params, _session, socket) do
    band = socket.assigns.band

    {:ok,
     socket
     |> assign(:page_title, "Repertório da #{band.name}")
     |> load_repertoire()}
  end

  defp load_repertoire(socket) do
    entries = Repertoire.list_band_repertoire(socket.assigns.band)

    socket
    |> assign(:entries, entries)
    |> assign(:entries_count, length(entries))
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

      <div
        :if={@entries_count == 0}
        id="repertoire-empty"
        class="text-muted-foreground py-8 text-center"
      >
        Nenhuma música no repertório ainda.
      </div>

      <.table :if={@entries_count > 0} id="repertoire" rows={@entries}>
        <:col :let={entry} label="Música">
          <span class="font-medium">{entry.song.title}</span>
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
