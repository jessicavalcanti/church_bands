defmodule ChurchBandsWeb.BandRepertoireLive.Form do
  @moduledoc """
  Vincula uma música do catálogo ao repertório de uma banda (US 2.2), no tom em
  que a banda a toca.

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_band_repertoire_manager`, que também carrega `@band`): Líder da
  própria banda, Pastor ou Líder de Louvor.

  **Não se cadastra música por aqui.** A lista é o catálogo (US 2.1) menos o que
  a banda já tem — quem precisa de uma música nova passa por `/songs`, e o
  recado abaixo do campo diz isso em vez de deixar quem procura atrás de um
  botão que não existe.

  O campo de música é um dropdown de candidatas com uma busca ao lado que apenas
  o estreita, **mesmo padrão de `MemberLive.Form`**, inclusive o cuidado de
  manter a música já escolhida visível quando a busca muda. A busca é a mesma do
  catálogo (US 2.5), reaproveitada do contexto e não copiada.

  **O tom é obrigatório e vem de uma lista fechada de 24**, agrupada em maiores
  e menores. Ele é da banda, não da música: a mesma música entra em D numa banda
  e em C na outra, e o catálogo não tem tom.

  Vincula-se uma música por vez, porque cada vínculo tem seu próprio tom. Depois
  de salvar, a tela devolve para o repertório: a lista mudando é o retorno
  visível do que se fez.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.BandRepertoire

  @impl true
  def mount(_params, _session, socket) do
    band = socket.assigns.band

    {:ok,
     socket
     |> assign(:page_title, "Adicionar música ao repertório da #{band.name}")
     |> assign(:form, to_form(Repertoire.change_band_repertoire()))
     |> assign(:key_options, BandRepertoire.key_options())
     |> load_candidates("")}
  end

  @impl true
  def handle_event("validate", %{"band_repertoire" => params} = payload, socket) do
    changeset = Repertoire.change_band_repertoire(%BandRepertoire{}, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> maybe_load_candidates(Map.get(payload, "search", ""))}
  end

  def handle_event("save", %{"band_repertoire" => params}, socket) do
    band = socket.assigns.band
    {song_id, attrs} = Map.pop(params, "song_id")

    case Repertoire.add_song_to_band(band, song_id, attrs) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{entry.song.title} entrou no repertório da #{band.name}.")
         |> push_navigate(to: ~p"/bands/#{band.id}/repertoire")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  # Qual música se pode vincular não depende do tom escolhido: só o texto da
  # busca refaz a consulta. É o mesmo cuidado de `MemberLive.Form`.
  defp maybe_load_candidates(socket, search) do
    if search == socket.assigns.search,
      do: socket,
      else: load_candidates(socket, search)
  end

  # A busca não escolhe nada: ela só estreita o dropdown. A música já
  # selecionada continua na lista mesmo que deixe de casar com o texto — senão
  # digitar depois de escolher apagaria a escolha.
  defp load_candidates(socket, search) do
    candidates = Repertoire.list_repertoire_candidates(socket.assigns.band, search)
    selected = selected_song(socket, candidates)

    socket
    |> assign(:search, search)
    |> assign(:song_options, song_options(candidates, selected))
  end

  defp selected_song(socket, candidates) do
    case socket.assigns.form[:song_id].value do
      nil ->
        nil

      "" ->
        nil

      id ->
        id = to_string(id)

        # Fora do filtro, a música é buscada pelo id — uma consulta por uma
        # linha, e não o catálogo inteiro de volta a cada tecla digitada.
        Enum.find(candidates, &(to_string(&1.id) == id)) || Repertoire.get_song(id)
    end
  end

  defp song_options(candidates, selected) do
    candidates
    |> maybe_prepend(selected)
    |> Enum.map(&{song_label(&1), &1.id})
  end

  # O artista entra no rótulo porque o catálogo permite dois títulos iguais de
  # propósito (US 2.1) — sem ele, as duas linhas do dropdown seriam idênticas.
  # O artista em branco chega como `nil`: o `cast/3` do Ecto lê texto vazio como
  # ausência, então não há um terceiro caso de string vazia para tratar aqui.
  defp song_label(%{artist: nil} = song), do: song.title
  defp song_label(song), do: "#{song.title} — #{song.artist}"

  defp maybe_prepend(candidates, nil), do: candidates

  defp maybe_prepend(candidates, selected) do
    if Enum.any?(candidates, &(&1.id == selected.id)),
      do: candidates,
      else: [selected | candidates]
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
      breadcrumb={[
        {"Bandas", ~p"/bands"},
        {@band.name, ~p"/bands/#{@band.id}"},
        {"Repertório", ~p"/bands/#{@band.id}/repertoire"},
        {"Adicionar música", nil}
      ]}
    >
      <:actions>
        <.link
          id="back-to-repertoire"
          navigate={~p"/bands/#{@band.id}/repertoire"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar para o repertório
        </.link>
      </:actions>

      <.header>
        {@page_title}
        <:subtitle>
          Escolha uma música do catálogo e o tom em que esta banda a toca.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="repertoire-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.form_item>
          <.form_label for="song-search">Filtrar a lista</.form_label>
          <.input
            type="text"
            name="search"
            id="song-search"
            value={@search}
            placeholder="Título ou artista"
            autocomplete="off"
            phx-debounce="300"
          />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:song_id]}>Música</.form_label>
          <.select field={@form[:song_id]} prompt="Escolha a música" options={@song_options} />
          <.form_message field={@form[:song_id]} />

          <p :if={@song_options == []} id="no-candidates" class="text-muted-foreground text-sm">
            {if String.trim(@search) == "",
              do: "Todas as músicas do catálogo já estão no repertório desta banda.",
              else: "Nenhuma música do catálogo com esse título ou artista está fora do repertório."} Música que ainda não existe no catálogo se cadastra em Músicas, e só depois entra
            aqui.
          </p>
        </.form_item>

        <.form_item>
          <.form_label field={@form[:key]}>Tom</.form_label>
          <.select field={@form[:key]} prompt="Escolha o tom" options={@key_options} />
          <.form_message field={@form[:key]} />

          <p id="key-hint" class="text-muted-foreground text-sm">
            O tom é desta banda. A mesma música pode estar em outra banda num tom diferente.
          </p>
        </.form_item>

        <div class="pt-2">
          <.button phx-disable-with="Adicionando...">Adicionar ao repertório</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
