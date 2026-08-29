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

  **Tom e status se mudam na própria linha (US 2.3)**, e é o primeiro evento de
  escrita desta tela. Por isso a reconferência de permissão do servidor nasce
  aqui: qualquer usuário logado tem esta página na mão desde a US 2.6, e quem
  não pode editar pode disparar o evento pelo socket mesmo sem o seletor
  desenhado. `handle_event/3` pergunta de novo a `Bands.manage_repertoire?/2` e
  confere que o vínculo é mesmo desta banda, como `BandLive.Show` faz ao
  remover integrante — esconder o controle nunca é autorização.

  **Um formulário por linha, com os dois selects.** Mexer em qualquer um manda
  os dois valores, porque é uma linha só que está sendo corrigida; quem escolhe
  a frase da confirmação é a comparação com o que estava gravado. Os dois campos
  ficam em colunas diferentes da tabela, e um `<form>` não pode envolver `<td>`
  irmãos: o select de status fica fora do formulário e se liga a ele pelo
  atributo `form`, que é como o HTML resolve exatamente este caso.

  A confirmação não é enfeite: ao arquivar com o filtro no padrão, a linha some
  da tela, e sem o flash não sobraria sinal de que a ação funcionou.

  **Remover do repertório (US 2.4) é a segunda escrita da linha**, e reusa o
  desenho da primeira: mesmo `cond` de reconferência, mesma recarga com o filtro
  e a busca que estiverem valendo. **Desde a US 3.6 ela pode ser recusada**: a
  música que está no set de um evento futuro daquela banda não sai do
  repertório, e a mensagem nomeia até três cultos e resume o resto — quem
  formata é esta tela, como na trava de `delete_song/1`, porque quantos nomes
  cabem numa frase é decisão de quem a escreve.

  A confirmação do navegador aponta a alternativa — arquivar tira da lista sem
  perder o registro —, porque este é o único momento em que quem decide tem as
  duas saídas à vista. Remover não exclui a música do catálogo: ela continua
  lá, e a banda a menos aparece na contagem de `/songs`.

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

  **A lista se recarrega sozinha (#112)**, pelo mesmo filtro e busca que
  estiverem valendo (`reload_repertoire/1`) — adicionar, mudar tom/status ou
  remover uma música publica em `Realtime.band_repertoire_topic/1`, e é por
  isso que quem só lê vê a mudança de quem monta sem F5.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Realtime
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
        if connected?(socket), do: Realtime.subscribe(Realtime.band_repertoire_topic(band))

        {:ok,
         socket
         |> assign(:page_title, "Repertório da #{band.name}")
         |> assign(:band, band)
         |> assign(:status_filters, @status_filters)
         |> assign(:key_options, BandRepertoire.key_options())
         |> assign(:status_options, BandRepertoire.status_options())
         |> assign(
           :can_manage?,
           Bands.manage_repertoire?(socket.assigns.current_user, band)
         )}
    end
  end

  @impl true
  def handle_info(:band_repertoire_updated, socket) do
    {:noreply, reload_repertoire(socket)}
  end

  # Ver o comentário gêmeo em `SwapLive.Index`: sem esta cláusula, qualquer
  # mensagem que não seja `:band_repertoire_updated` derrubaria a LiveView.
  def handle_info(_message, socket), do: {:noreply, socket}

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

  # Reconsulta a permissão e confere que o vínculo é mesmo desta banda: os dois
  # vêm do navegador, e o id poderia apontar para o repertório de outra — cuja
  # permissão é outra. Mesma ordem de `BandLive.Show`.
  def handle_event("update_entry", %{"entry_id" => id} = params, socket) do
    %{"key" => key, "status" => status} = params
    entry = Repertoire.get_band_song(id)
    band = socket.assigns.band

    cond do
      not Bands.manage_repertoire?(socket.assigns.current_user, band) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Você não tem permissão para alterar o repertório desta banda."
         )}

      is_nil(entry) or entry.band_id != band.id ->
        {:noreply,
         socket
         |> put_flash(:error, "Música não encontrada no repertório desta banda.")
         |> reload_repertoire()}

      true ->
        case Repertoire.update_band_song(entry, %{"key" => key, "status" => status}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> put_flash(:info, change_message(entry, updated))
             |> reload_repertoire()}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "Não foi possível atualizar a música.")}
        end
    end
  end

  # Mesma ordem e mesmas duas perguntas do "update_entry" acima — e pela mesma
  # razão: qualquer usuário logado tem esta tela na mão desde a US 2.6, e o id
  # do vínculo vem do navegador.
  def handle_event("remove", %{"id" => id}, socket) do
    entry = Repertoire.get_band_song(id)
    band = socket.assigns.band

    cond do
      not Bands.manage_repertoire?(socket.assigns.current_user, band) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Você não tem permissão para remover músicas do repertório desta banda."
         )}

      is_nil(entry) or entry.band_id != band.id ->
        {:noreply,
         socket
         |> put_flash(:error, "Música não encontrada no repertório desta banda.")
         |> reload_repertoire()}

      true ->
        case Repertoire.remove_song_from_band(entry) do
          {:ok, entry} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{entry.song.title} saiu do repertório da #{band.name}.")
             |> reload_repertoire()}

          {:error, {:in_future_set, titles}} ->
            {:noreply, put_flash(socket, :error, in_future_set_message(entry, titles))}
        end
    end
  end

  # A recusa nomeia até três eventos e resume o resto, como a de
  # `SongLive.Index` faz com as bandas: a saída de quem quer remover é tirar a
  # música desses sets, e para isso é preciso saber quais são — mas uma frase
  # com doze títulos não se lê. Quem escolhe quantos cabem é a tela; o contexto
  # devolve a lista inteira.
  @named_events 3

  defp in_future_set_message(entry, titles) do
    "#{entry.song.title} está no set de #{event_list(titles)}. " <>
      "Tire-a desses sets antes de removê-la do repertório."
  end

  defp event_list(titles) do
    case Enum.split(titles, @named_events) do
      {named, []} -> Enum.join(named, ", ")
      {named, rest} -> "#{Enum.join(named, ", ")} e mais #{length(rest)}"
    end
  end

  # A frase sai da comparação com o que estava gravado, e não de um campo que
  # diga o que mudou. Não há ramo para "nada mudou": o `phx-change` não dispara
  # ao reescolher o mesmo valor, e ele ficaria sem teste que o alcançasse.
  defp change_message(%{status: status}, %{status: status} = updated),
    do: "#{updated.song.title} agora está no tom #{updated.key}."

  defp change_message(_entry, %{status: :ready} = updated),
    do: "#{updated.song.title} agora está pronta."

  defp change_message(_entry, %{status: :learning} = updated),
    do: "#{updated.song.title} voltou para em aprendizado."

  defp change_message(_entry, %{status: :archived} = updated),
    do: "#{updated.song.title} foi arquivada."

  # A lista volta com o filtro e a busca que estiverem valendo, e não no padrão:
  # quem arquivou uma música com o filtro em *Pronta* continua vendo as prontas.
  defp reload_repertoire(socket) do
    load_repertoire(socket, socket.assigns.search, socket.assigns.status)
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
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
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
          <form
            :if={@can_manage?}
            id={"repertoire-entry-#{entry.id}"}
            phx-change="update_entry"
            phx-submit="update_entry"
          >
            <input type="hidden" name="entry_id" value={entry.id} />
            <.select
              id={"repertoire-key-#{entry.id}"}
              name="key"
              value={to_string(entry.key)}
              options={@key_options}
              class="w-24"
              aria-label={"Tom de #{entry.song.title}"}
            />
          </form>
          <span :if={not @can_manage?} id={"repertoire-key-#{entry.id}"} class="font-medium">
            {entry.key}
          </span>
        </:col>
        <:col :let={entry} label="Status">
          <.select
            :if={@can_manage?}
            id={"repertoire-status-#{entry.id}"}
            name="status"
            form={"repertoire-entry-#{entry.id}"}
            value={to_string(entry.status)}
            options={@status_options}
            class="w-40"
            aria-label={"Status de #{entry.song.title}"}
          />
          <.badge :if={not @can_manage?} id={"repertoire-status-#{entry.id}"} variant="secondary">
            {BandRepertoire.status_label(entry.status)}
          </.badge>
        </:col>
        <:action :let={entry} :if={@can_manage?}>
          <.button
            id={"remove-repertoire-song-#{entry.id}"}
            variant="destructive"
            size="sm"
            phx-click="remove"
            phx-value-id={entry.id}
            data-confirm={
              "Remover \"#{entry.song.title}\" do repertório da #{@band.name}?\n\n" <>
                "Para só tirar da lista sem perder o registro, marque como arquivada."
            }
          >
            Remover
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
