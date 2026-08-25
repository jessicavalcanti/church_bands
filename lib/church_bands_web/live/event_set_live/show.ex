defmodule ChurchBandsWeb.EventSetLive.Show do
  @moduledoc """
  O set de uma banda escalada num evento (US 3.6): o que ela toca naquele
  culto, na ordem e no tom em que toca.

  **Tela própria, e não mais um bloco em `/events/:id`.** A tela do evento
  responde "o que é este culto e quem toca nele", e é de leitura ampla; esta
  responde "o que a *minha* banda toca aqui", e é de quem monta. Uma
  responsabilidade e uma permissão cada.

  **Ler é de qualquer um logado (US 3.7); montar continua sendo de quem
  monta.** Ela nasceu inteira restrita na US 3.6, e abriu aqui pelo mesmo
  motivo do catálogo e do repertório: quem toca precisa saber o que vai tocar,
  e quem não toca — o pastor, quem opera o som — tem interesse legítimo. O que
  a `live_session` ainda garante (`:ensure_event_band`) é o par existir: o
  evento e a banda escalada nele, em `@event`, `@event_band` e `@band`.

  **Quem escreve é `Schedule.manage_set?/2`**: acesso total, ou o Líder
  **daquela** banda — o líder de outra banda escalada no mesmo culto edita o
  evento inteiro e não mexe no set alheio. Ela decide o que a tela desenha e é
  **perguntada de novo em cada um dos quatro `handle_event`**, como em
  `BandRepertoireLive.Show`: a tela está na mão de qualquer usuário logado, e
  quem sabe disso dispara o evento pelo socket sem controle nenhum desenhado.
  Esconder o botão nunca foi autorização.

  O que os eventos de escrita reconferem **também** é de quem é a linha: o id
  do item vem do navegador, e `Schedule.get_set_item/2` recebe a escala junto
  para que o id forjado do set de outra banda não case com nada.

  **Quem não monta não tem alça de arraste.** A ordem é informação, não
  controle, e uma alça que não funciona é pior do que alça nenhuma — quem
  desenha a linha é `EventSetComponents.set_row/1`, a mesma da tela do evento.

  **A ordem é manual, arrastando** (hook `SetOrder`, sobre a API nativa do
  HTML). É o gesto que a informação pede: a sequência do culto é o assunto da
  tela. E **a ordem que chega do navegador não é confiável** — o hook manda a
  lista de ids e `Schedule.reorder_set/2` recusa o conjunto que não for
  exatamente o do set. Quem tem o console aberto manda o que quiser.

  **O tom tem três estados na linha**, e quem os resolve é
  `EventSetComponents.effective_key/2` — num lugar só, para que esta tela e a
  do evento não tenham como discordar.

  **Adicionar não esconde o que já está no set**, ao contrário de todo outro
  seletor do sistema: repetir é regra aqui — há quem abra e encerre o culto com
  a mesma canção.
  """
  use ChurchBandsWeb, :live_view

  import ChurchBandsWeb.EventSetComponents

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
     |> assign(:can_manage?, manage_set?(socket))
     |> load_set()}
  end

  @impl true
  def handle_event("add", %{"set_song" => %{"song_id" => song_id}}, socket) do
    with_permission(socket, fn ->
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
           |> put_flash(
             :error,
             "Escolha uma música do repertório da #{socket.assigns.band.name}."
           )
           |> load_set()}
      end
    end)
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
    with_permission(socket, fn ->
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
    end)
  end

  # A tela abriu para quem não escreve nela (US 3.7), e por isso as quatro
  # escritas voltam a perguntar ao contexto antes de agir. A pergunta é feita
  # de novo, e não lida de `@can_manage?`: o assign é o que a tela desenhou no
  # mount, e quem dispara o evento pelo socket não passou por desenho nenhum.
  defp with_permission(socket, write) do
    if manage_set?(socket) do
      write.()
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Você não tem permissão para montar o set desta banda neste evento."
       )}
    end
  end

  defp manage_set?(socket),
    do: Schedule.manage_set?(socket.assigns.current_user, socket.assigns.event_band)

  # Os dois eventos de linha fazem duas perguntas antes de agir — **quem está
  # mexendo pode?** e **esta linha é deste set?**. A segunda é o par escala +
  # id: o id vem do navegador e poderia apontar para o set de outra banda no
  # mesmo culto.
  defp with_item(socket, id, write) do
    with_permission(socket, fn ->
      case Schedule.get_set_item(socket.assigns.event_band, id) do
        nil ->
          {:noreply,
           socket
           |> put_flash(:error, "Música não encontrada neste set.")
           |> load_set()}

        item ->
          {:noreply, write.(item)}
      end
    end)
  end

  # A frase sai da comparação com o que estava gravado, como em
  # `BandRepertoireLive.Show`: é o mesmo evento que grava a exceção e que a
  # limpa, e o que muda entre os dois é só o valor que chegou.
  defp key_message(_item, %{key: nil} = updated),
    do: "#{updated.song.title} voltou para o tom da banda."

  defp key_message(_item, updated),
    do: "#{updated.song.title} fica em #{updated.key} neste evento."

  defp load_set(socket) do
    socket
    |> assign(:set, Schedule.list_set(socket.assigns.event_band))
    |> assign_candidates()
  end

  # As candidatas só interessam a quem monta: para quem está apenas lendo o que
  # a banda vai tocar, essa consulta não teria leitor. Mesmo arranjo de
  # `EventLive.Show` com as bandas escaláveis.
  defp assign_candidates(%{assigns: %{can_manage?: false}} = socket),
    do: assign(socket, :candidates, [])

  defp assign_candidates(socket),
    do: assign(socket, :candidates, Schedule.list_set_candidates(socket.assigns.event_band))

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
        phx-hook={@can_manage? && "SetOrder"}
        class="divide-border border-border mt-6 divide-y rounded-md border"
      >
        <.set_row
          :for={{item, index} <- Enum.with_index(@set, 1)}
          item={item}
          index={index}
          editable={@can_manage?}
          key_options={@key_options}
          band_name={@band.name}
        />
      </ol>

      <p :if={@set == []} id="set-empty" class="text-muted-foreground mt-6 text-sm">
        Nenhuma música no set ainda.
      </p>

      <div :if={@can_manage?} class="mt-8">
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
end
