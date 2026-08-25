defmodule ChurchBandsWeb.EventSetLive.Show do
  @moduledoc """
  O set de uma banda escalada num evento (US 3.6): o que ela toca naquele
  culto, na ordem e no tom em que toca.

  **Tela própria, e não mais um bloco em `/events/:id`.** A tela do evento
  responde "o que é este culto e quem toca nele", e é de leitura ampla; esta
  responde "o que a *minha* banda toca aqui", e é de quem monta. Uma
  responsabilidade e uma permissão cada.

  **Nesta história ela é só de quem monta**, músico comum incluído na recusa. A
  autorização acontece inteira na `live_session` do router
  (`:ensure_event_set_manager`, que carrega `@event`, `@event_band` e `@band`):
  acesso total, ou o Líder **daquela** banda — o líder de outra banda escalada
  no mesmo culto não mexe no set alheio. Por isso os `handle_event` **não**
  reconferem a permissão, ao contrário de `EventLive.Show` e de
  `BandRepertoireLive.Show`: aquelas telas abrem para quem não pode agir nelas,
  e esta não abre. Quando a US 3.7 liberar a leitura, a reconferência nasce
  junto — é o mesmo caminho que o repertório fez da US 2.2 para a 2.6.

  O que os eventos de escrita reconferem é **de quem é a linha**: o id do item
  vem do navegador, e `Schedule.get_set_item/2` recebe a escala junto para que
  o id forjado do set de outra banda não case com nada.

  **A ordem é manual, arrastando** (hook `SetOrder`, sobre a API nativa do
  HTML). É o gesto que a informação pede: a sequência do culto é o assunto da
  tela. E **a ordem que chega do navegador não é confiável** — o hook manda a
  lista de ids e `Schedule.reorder_set/2` recusa o conjunto que não for
  exatamente o do set. Quem tem o console aberto manda o que quiser.

  **O tom tem três estados na linha**, e é por isso que ele não é um campo só:

    * o tom **da banda**, herdado do repertório, quando não há exceção
    * o tom **deste evento**, quando alguém gravou um — e aí a linha continua
      dizendo em que tom a banda toca, senão a exceção pareceria a regra
    * **nenhum dos dois**, quando a música saiu do repertório depois de entrar
      no set. A trava de remoção só segura evento futuro, então o set de um
      culto passado alcança este caso — a linha mostra <q>—</q> e diz por quê,
      em vez de um espaço em branco sem explicação

  **Adicionar não esconde o que já está no set**, ao contrário de todo outro
  seletor do sistema: repetir é regra aqui — há quem abra e encerre o culto com
  a mesma canção.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.LocalTime
  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Schedule

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Set da #{socket.assigns.band.name}")
     |> assign(:add_form, to_form(%{}, as: :set_song))
     |> assign(:key_options, BandRepertoire.key_options())
     |> load_set()}
  end

  @impl true
  def handle_event("add", %{"set_song" => %{"song_id" => song_id}}, socket) do
    case Schedule.add_song_to_set(socket.assigns.event_band, song_id) do
      {:ok, item} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{item.song.title} entrou no set.")
         |> load_set()}

      # Música fora do repertório, música arquivada, música que não existe e id
      # que não é um id são a mesma recusa para quem lê: **não é uma escolha
      # válida**. Os quatro só se alcançam forçando o formulário — o seletor é
      # obrigatório e só oferece o repertório não arquivado —, e quatro
      # mensagens quase iguais seriam quatro textos para manter alinhados sem
      # ninguém para ler a diferença.
      {:error, :not_in_repertoire} ->
        {:noreply,
         socket
         |> put_flash(:error, "Escolha uma música do repertório da #{socket.assigns.band.name}.")
         |> load_set()}
    end
  end

  def handle_event("update_key", %{"item_id" => id, "key" => key}, socket) do
    with_item(socket, id, fn item ->
      case Schedule.update_set_item(item, %{"key" => key}) do
        {:ok, updated} ->
          socket
          |> put_flash(:info, key_message(item, updated))
          |> load_set()

        # Só alcançável forçando o socket: o seletor tem os 24 tons e a opção
        # vazia, e o `Ecto.Enum` recusa o resto.
        {:error, %Ecto.Changeset{}} ->
          put_flash(socket, :error, "Escolha um tom da lista.")
      end
    end)
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with_item(socket, id, fn item ->
      {:ok, item} = Schedule.remove_from_set(item)

      socket
      |> put_flash(:info, "#{item.song.title} saiu do set.")
      |> load_set()
    end)
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    case Schedule.reorder_set(socket.assigns.event_band, ids) do
      :ok ->
        {:noreply, load_set(socket)}

      # A lista chega do hook de arraste, e o único jeito de ela divergir do
      # set é alguém a ter escrito à mão. Recarregar é o que devolve à tela a
      # ordem que está gravada, desfazendo o que o DOM mostrava.
      {:error, :mismatched_set} ->
        {:noreply,
         socket
         |> put_flash(:error, "Não foi possível gravar a ordem do set.")
         |> load_set()}
    end
  end

  # Os dois eventos de linha fazem a mesma pergunta antes de agir — **esta
  # linha é deste set?** —, e o par escala + id é o que a responde: o id vem do
  # navegador e poderia apontar para o set de outra banda no mesmo culto.
  defp with_item(socket, id, write) do
    case Schedule.get_set_item(socket.assigns.event_band, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Música não encontrada neste set.")
         |> load_set()}

      item ->
        {:noreply, write.(item)}
    end
  end

  # A frase sai da comparação com o que estava gravado, como em
  # `BandRepertoireLive.Show`: é o mesmo evento que grava a exceção e que a
  # limpa, e o que muda entre os dois é só o valor que chegou.
  defp key_message(_item, %{key: nil} = updated),
    do: "#{updated.song.title} voltou para o tom da banda."

  defp key_message(_item, updated),
    do: "#{updated.song.title} fica em #{updated.key} neste evento."

  defp load_set(socket) do
    event_band = socket.assigns.event_band

    socket
    |> assign(:set, Schedule.list_set(event_band))
    |> assign(:candidates, Schedule.list_set_candidates(event_band))
  end

  # O artista entra no rótulo porque o catálogo permite dois títulos iguais de
  # propósito (US 2.1) — sem ele, as duas linhas do seletor seriam idênticas. O
  # tom entra porque é a informação que decide entre duas versões da mesma
  # música no repertório.
  defp candidate_label(%{song: %{artist: nil}} = entry), do: "#{entry.song.title} (#{entry.key})"

  defp candidate_label(entry),
    do: "#{entry.song.title} — #{entry.song.artist} (#{entry.key})"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[
        {"Calendário", ~p"/calendar"},
        {@event.title, ~p"/events/#{@event.id}"},
        {@band.name, ~p"/bands/#{@band.id}"},
        {"Set", nil}
      ]}
    >
      <:actions>
        <.link
          id="back-to-event"
          navigate={~p"/events/#{@event.id}"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar para o evento
        </.link>
        <.link
          id="set-band-repertoire"
          navigate={~p"/bands/#{@band.id}/repertoire"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          Repertório da banda
        </.link>
      </:actions>

      <.header>
        Set da {@band.name}
        <:subtitle>
          <span id="set-event">
            {@event.title} · {LocalTime.format(@event.starts_at, :date)} às {LocalTime.format(
              @event.starts_at,
              :time
            )}
          </span>
          <.badge :if={@event.status == :cancelled} id="set-event-cancelled" variant="outline">
            Cancelado
          </.badge>
        </:subtitle>
      </.header>

      <ol
        :if={@set != []}
        id="set-songs"
        phx-hook="SetOrder"
        class="divide-border border-border mt-6 divide-y rounded-md border"
      >
        <li
          :for={{item, index} <- Enum.with_index(@set, 1)}
          id={"set-song-#{item.id}"}
          data-set-item={item.id}
          draggable="true"
          class="flex items-start gap-3 p-3 data-[dragging]:opacity-50"
        >
          <span class="text-muted-foreground cursor-grab pt-2" aria-hidden="true">
            <.icon name="hero-bars-3" class="size-4" />
          </span>

          <span
            id={"set-position-#{item.id}"}
            class="text-muted-foreground w-6 pt-2 text-right text-sm tabular-nums"
          >
            {index}
          </span>

          <div class="min-w-0 flex-1 pt-1">
            <p class="font-medium">{item.song.title}</p>
            <p :if={item.song.artist} class="text-muted-foreground text-sm">{item.song.artist}</p>
          </div>

          <div class="w-44">
            <p id={"set-key-#{item.id}"} class="font-medium">{playing_key(item)}</p>

            <p id={"set-key-note-#{item.id}"} class="text-muted-foreground mt-0.5 text-xs">
              {key_note(item)}
            </p>

            <form id={"set-key-form-#{item.id}"} phx-change="update_key" class="mt-1">
              <input type="hidden" name="item_id" value={item.id} />
              <.select
                id={"set-event-key-#{item.id}"}
                name="key"
                value={to_string(item.key)}
                prompt="Tom da banda"
                options={@key_options}
                class="h-8 text-xs"
                aria-label={"Tom de #{item.song.title} neste evento"}
              />
            </form>
          </div>

          <.button
            id={"remove-set-song-#{item.id}"}
            variant="ghost"
            size="sm"
            phx-click="remove"
            phx-value-id={item.id}
            data-confirm={"Tirar \"#{item.song.title}\" do set?\n\nEla continua no repertório da #{@band.name}."}
          >
            Remover
          </.button>
        </li>
      </ol>

      <p :if={@set == []} id="set-empty" class="text-muted-foreground mt-6 text-sm">
        Nenhuma música no set ainda.
      </p>

      <div class="mt-8">
        <.header>
          Adicionar música
          <:subtitle>
            Do repertório da {@band.name}, menos as arquivadas. Ela entra no fim da sequência.
          </:subtitle>
        </.header>

        <.form
          :if={@candidates != []}
          for={@add_form}
          id="add-set-song-form"
          phx-submit="add"
          class="mt-4 flex items-end gap-2"
        >
          <div class="flex-1">
            <.form_item>
              <.form_label field={@add_form[:song_id]}>Música</.form_label>
              <.select
                field={@add_form[:song_id]}
                prompt="Escolha a música"
                options={Enum.map(@candidates, &{candidate_label(&1), &1.song_id})}
                required
              />
            </.form_item>
          </div>
          <.button phx-disable-with="Adicionando...">Adicionar</.button>
        </.form>

        <p :if={@candidates == []} id="set-no-candidates" class="text-muted-foreground mt-4 text-sm">
          O repertório desta banda está vazio.
          <.link navigate={~p"/bands/#{@band.id}/repertoire"} class="underline underline-offset-4">
            Monte o repertório da {@band.name}
          </.link>
          antes de montar o set.
        </p>
      </div>
    </Layouts.app>
    """
  end

  # O tom que vale na hora de tocar: a exceção deste evento quando há uma, o do
  # repertório quando não há. O travessão é o terceiro caso — a música saiu do
  # repertório depois de entrar no set, e não há tom nenhum a mostrar.
  defp playing_key(%{key: nil, band_key: nil}), do: "—"
  defp playing_key(%{key: nil, band_key: band_key}), do: to_string(band_key)
  defp playing_key(%{key: key}), do: to_string(key)

  # E a nota embaixo dele diz **de onde ele veio**, que é a informação que o
  # tom sozinho esconde: sem ela, "C" numa banda que toca em D pareceria o tom
  # da banda. São quatro cláusulas em vez de um `cond` no HEEx — é vocabulário
  # da tela, e a regra de qual estado está valendo não devia ficar espalhada no
  # template.
  defp key_note(%{key: nil, band_key: nil}), do: "Fora do repertório da banda"
  defp key_note(%{key: nil, band_key: band_key}), do: "Tom da banda: #{band_key}"
  defp key_note(%{band_key: nil}), do: "Só deste evento · fora do repertório da banda"
  defp key_note(%{band_key: band_key}), do: "Só deste evento · a banda toca em #{band_key}"
end
