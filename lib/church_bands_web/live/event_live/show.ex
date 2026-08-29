defmodule ChurchBandsWeb.EventLive.Show do
  @moduledoc """
  Detalhe de um evento da agenda.

  **Ler é de qualquer um logado (US 3.3).** A tela nasceu inteira restrita na
  US 3.2 e abriu na 3.3, junto com a grade: quem toca chega neste endereço pelo
  calendário, e é aqui que estão a hora, o local, as observações e — desde a
  US 3.4 — **quem toca**.

  **Escrever se divide em três alturas (US 3.4)**, e é por isso que há três
  perguntas de permissão em vez de uma:

    * **Editar, Cancelar e Reabrir** são de quem `Schedule.manage_event?/2`
      aceita: acesso total, ou o Líder de Banda de uma banda escalada aqui, se
      o tipo permitir que ele crie
    * **Excluir** é só de acesso total — apagar o registro é para todo mundo, e
      não só para a banda de quem clicou
    * **Escalar e desescalar** também são só de acesso total: quem decide quem
      toca no culto é quem responde pela agenda. O líder não tira nem a própria
      banda do próprio ensaio; o que ele pode fazer é cancelá-lo

  **Cada `handle_event` de escrita reconfere a permissão no servidor** desde a
  US 3.3, quando a tela passou a receber quem não pode agir nela. Esconder o
  botão nunca foi autorização — o evento chega pelo socket, e quem sabe disso o
  dispara sem botão nenhum. É o mesmo cuidado de `BandLive.Show` e de
  `SongLive.Index`.

  **Cancelar e reabrir são um par mutuamente exclusivo pelo status**, e não um
  botão que alterna: o rótulo diz o que vai acontecer, e num evento que a
  igreja divulgou não se clica em "alternar" por engano.

  **Cancelar preserva e excluir apaga**, e as duas coisas existem porque são
  perguntas diferentes. Cancelar é "não vai ter" — e o evento continua no
  calendário, riscado, senão quem não olhar de novo aparece no domingo.
  Excluir é "isto nunca deveria existir", e é por isso que a confirmação nomeia
  o evento.

  **O set nasce aqui (US 3.6)**, pendurado em cada banda escalada: o link
  *Montar set* aparece por banda, e só para quem monta o set **daquela** —
  `Schedule.manage_set?/2`, que é uma pergunta mais estreita do que a de
  editar o evento. O Líder de uma banda escalada edita o culto inteiro e monta
  o set só do que é dele.

  **E desde a US 3.7 o set aparece inteiro aqui, e não só o link para ele.**
  É neste endereço que as pessoas chegam — pelo calendário, pelo bloco do
  portal, por um link mandado no grupo —, e obrigá-las a um clique a mais por
  banda escalada para ver o que interessa seria esconder a informação atrás da
  estrutura. Quem desenha cada linha é `EventSetComponents.set_row/1`, a mesma
  da tela do set, com `editable: false`: aqui a ordem é informação, não
  controle.

  **Os sets das bandas saem de uma consulta só** (`list_sets_for_event/1`), e
  não de uma por banda: a escala cresce com o número de bandas do culto, e uma
  consulta por linha é o tipo de coisa que ninguém vê acontecer. É de lá que
  sai também a contagem do <q>N no set</q> e da confirmação de desescalar —
  contar o que já está na mão não custa consulta nenhuma.

  **Desde a US 4.1 cada banda escalada mostra também o elenco dela** — quem
  toca, e a função de cada um —, acima do set: o set é o que a banda vai tocar,
  e o elenco é quem vai tocar. Quem abre o evento pergunta primeiro *quem*.
  A lista é a mesma de `/bands/:id`, escrita pela mesma função
  (`Bands.list_rosters/1`): duas telas que respondem <q>quem toca nesta
  banda</q> com listas diferentes seriam a mesma pergunta com duas respostas.
  Por isso o Líder de Banda sem vínculo aparece aqui também, com <q>Sem função
  definida</q>.

  **O elenco é derivado de `band_members`, não copiado para o evento**, e é a
  decisão que atravessa a Fase 4: escalar uma banda escala quem está nela
  **hoje**. A consequência é assumida — um evento passado mostra o elenco
  atual. Os elencos saem de **uma** chamada só, como os sets, pelo mesmo
  motivo.

  **E desde a US 4.2 cada linha do elenco pode virar um pedido de troca.** O
  botão *Solicitar troca* aparece só sobre quem faz a **sua** função em outra
  banda, num evento futuro em que você não está — é assim que se procura
  substituto de verdade: olhando o calendário para achar um domingo em que
  outra banda toca. Quem decide onde ele aparece é `Swaps.requestable_member_ids/2`,
  chamada **uma vez** para a tela inteira: perguntar por linha do elenco seria
  uma consulta por integrante, e o elenco de um culto com duas bandas já passa
  de dez linhas. Esconder o botão continua não sendo autorização — quem forçar
  `/events/:id/members/:member_id/swap` é recusado pelo hook, antes do mount.

  **E desde a US 4.3 a vaga trocada mostra quem vai tocar no lugar do titular**,
  com a marca *Provisório* e o <q>no lugar de {nome}</q>. A troca aceita **não
  vira linha de escala**: ela é exceção sobre o elenco derivado, e é por isso
  que a lista continua na ordem da vaga, com o substituto na posição de quem
  saiu — quem lê o elenco continua lendo por função. O par que faz isso é
  `Swaps.list_accepted_for_event/1` (**uma** consulta a mais na tela, não uma
  por banda) e `Swaps.apply_to_rosters/2`.

  **A vaga já trocada não recebe outro pedido**, e por isso o botão *Solicitar
  troca* some dela: a vaga mudou de dono uma vez, e trocar troca de novo seria
  a cadeia de troca sobre troca que a Fase 4 deixou de fora de propósito.

  **Desescalar passou a contar as músicas** na confirmação, e é a regra que a
  US 3.4 deixou para cá: o set vai junto pelo `on_delete: :delete_all`, e uma
  confirmação que não diz isso faz perder meia hora de trabalho por um clique
  que parecia inofensivo. Banda sem set continua com a frase simples — anunciar
  "0 músicas" seria ruído.
  """
  use ChurchBandsWeb, :live_view

  import ChurchBandsWeb.EventSetComponents

  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule
  alias ChurchBands.Swaps

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Schedule.get_event(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Evento não encontrado.")
         |> push_navigate(to: ~p"/calendar")}

      event ->
        {:ok,
         socket
         |> assign_event(event)
         |> assign(:can_manage?, Schedule.manage_event?(socket.assigns.current_user, event))
         |> assign(:schedule_form, to_form(%{}, as: :event_band))
         |> load_bands()}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    with_permission(socket, socket.assigns.can_manage?, fn event ->
      {:ok, event} = Schedule.cancel_event(event)

      socket
      |> put_flash(:info, "Evento #{event.title} cancelado.")
      |> assign_event(event)
    end)
  end

  def handle_event("reopen", _params, socket) do
    with_permission(socket, socket.assigns.can_manage?, fn event ->
      case Schedule.reopen_event(event) do
        {:ok, event} ->
          socket
          |> put_flash(:info, "Evento #{event.title} reaberto.")
          |> assign_event(event)

        {:error, {:conflict, band, other}} ->
          put_flash(socket, :error, conflict_message(band, other))
      end
    end)
  end

  def handle_event("delete", _params, socket) do
    with_permission(socket, socket.assigns.full_access?, fn event ->
      case Schedule.delete_event(event) do
        {:ok, event} ->
          socket
          |> put_flash(:info, "Evento #{event.title} excluído.")
          |> push_navigate(to: ~p"/calendar")

        {:error, {:scheduled, count}} ->
          put_flash(socket, :error, scheduled_message(event, count))
      end
    end)
  end

  def handle_event("schedule", %{"event_band" => %{"band_id" => band_id}}, socket) do
    with_permission(socket, socket.assigns.full_access?, fn event ->
      case Schedule.schedule_band(event, band_id) do
        {:ok, event_band} ->
          socket
          |> put_flash(:info, "#{event_band.band.name} escalada em #{event.title}.")
          |> load_bands()

        {:error, {:conflict, other}} ->
          put_flash(socket, :error, conflict_message(Bands.get_band(band_id), other))

        # Banda repetida, banda que não existe e banda nenhuma são a mesma
        # recusa para quem lê: **a banda mandada não é uma escolha válida**. Os
        # três só se alcançam forçando o formulário — o seletor é obrigatório e
        # já esconde as escaladas —, e três mensagens quase iguais seriam três
        # textos para manter alinhados sem ninguém para ler a diferença.
        {:error, %Ecto.Changeset{}} ->
          put_flash(socket, :error, "Escolha uma banda da lista que ainda não está escalada.")
      end
    end)
  end

  def handle_event("unschedule", %{"id" => band_id}, socket) do
    with_permission(socket, socket.assigns.full_access?, fn event ->
      # O par evento + banda é o que se procura, e não o id da linha: assim o
      # id forjado da escala de outro evento não casa com nada em vez de
      # apagar uma escala que não é desta tela.
      case Schedule.get_event_band(event.id, band_id) do
        nil ->
          socket
          |> put_flash(:error, "Esta banda não está escalada neste evento.")
          |> load_bands()

        event_band ->
          {:ok, event_band} = Schedule.unschedule_band(event_band)

          socket
          |> put_flash(:info, "#{event_band.band.name} saiu da escala de #{event.title}.")
          |> load_bands()
      end
    end)
  end

  # As escritas desta tela são a mesma pergunta antes de fazer coisas
  # diferentes — só que desde a US 3.4 não é a mesma pergunta para todas: o
  # Líder de Banda cancela o próprio ensaio e não exclui nem desescala nada.
  # Por isso quem chama diz qual permissão vale, e a recusa é uma só.
  defp with_permission(socket, true, write), do: {:noreply, write.(socket.assigns.event)}

  defp with_permission(socket, false, _write) do
    {:noreply, put_flash(socket, :error, "Você não tem permissão para alterar este evento.")}
  end

  defp conflict_message(band, event),
    do: "#{band.name} já está escalada em #{event.title}, no mesmo horário."

  defp scheduled_message(event, count),
    do: "#{event.title} tem #{bands_count(count)}. Cancele o evento em vez de excluí-lo."

  defp bands_count(1), do: "1 banda escalada"
  defp bands_count(count), do: "#{count} bandas escaladas"

  defp assign_event(socket, event) do
    socket
    |> assign(:event, event)
    |> assign(:page_title, event.title)
  end

  defp load_bands(socket) do
    socket
    |> assign(:requestable, requestable_members(socket))
    |> assign(:event_bands, decorate_bands(socket))
    |> assign_schedulable_bands()
  end

  # A quem **quem está olhando** pode pedir troca neste evento, numa pergunta
  # só para a tela inteira. Vem antes de `decorate_bands/1` e fora dele porque
  # a resposta é do evento, e não de cada banda escalada: o `MapSet` atravessa
  # o elenco inteiro, de todas as bandas.
  defp requestable_members(socket) do
    Swaps.requestable_member_ids(socket.assigns.current_user, socket.assigns.event)
  end

  # Cada linha da escala precisa de três coisas que não estão nela: se **quem
  # está olhando** monta o set daquela banda, qual é o set dela e quem toca
  # nela. As três viram campo da linha aqui, e não `:if` com chamada de
  # contexto no HEEx — o template não deveria consultar o banco.
  #
  # Os sets e os elencos vêm todos de uma vez, antes do `Enum.map/2`: pedi-los
  # dentro dele seria uma consulta por banda escalada. A contagem que a
  # confirmação de desescalar mostra sai daí também, contando o que já está na
  # mão.
  defp decorate_bands(socket) do
    event_bands = Schedule.list_event_bands(socket.assigns.event)
    sets = Schedule.list_sets_for_event(socket.assigns.event)

    rosters =
      event_bands
      |> Enum.map(& &1.band_id)
      |> Bands.list_rosters()
      |> Swaps.apply_to_rosters(Swaps.list_accepted_for_event(socket.assigns.event))

    Enum.map(event_bands, fn event_band ->
      %{
        event_band: event_band,
        can_manage_set?: Schedule.manage_set?(socket.assigns.current_user, event_band),
        set: Map.get(sets, event_band.id, []),
        roster: Map.get(rosters, event_band.band_id, [])
      }
    end)
  end

  # A confirmação de desescalar diz o que se está perdendo junto. Sem set, a
  # frase da US 3.4 continua inteira: dizer "as 0 músicas do set dela" seria
  # anunciar uma perda que não existe.
  defp unschedule_confirm(%{event_band: event_band, set: []}),
    do: "Desescalar a #{event_band.band.name} deste evento?"

  defp unschedule_confirm(%{event_band: event_band, set: set}) do
    count = length(set)

    "Desescalar a #{event_band.band.name} deste evento? " <>
      "#{set_songs_count(count)} do set dela neste evento #{lost(count)}."
  end

  defp set_songs_count(1), do: "A 1 música"
  defp set_songs_count(count), do: "As #{count} músicas"

  defp lost(1), do: "será perdida"
  defp lost(_count), do: "serão perdidas"

  # As candidatas só interessam a quem escala: para quem está apenas olhando
  # quem toca, essa consulta não teria leitor.
  defp assign_schedulable_bands(%{assigns: %{full_access?: false}} = socket),
    do: assign(socket, :schedulable_bands, [])

  defp assign_schedulable_bands(socket),
    do: assign(socket, :schedulable_bands, Schedule.list_schedulable_bands(socket.assigns.event))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={[{"Calendário", ~p"/calendar"}, {@event.title, nil}]}
    >
      <:actions>
        <.link
          id="back-to-calendar"
          navigate={~p"/calendar"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar
        </.link>
        <.link
          :if={@can_manage?}
          id="edit-event"
          navigate={~p"/events/#{@event.id}/edit"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          Editar
        </.link>
        <.button
          :if={@can_manage? and @event.status == :scheduled}
          id="cancel-event"
          variant="outline"
          size="sm"
          phx-click="cancel"
          data-confirm={"Cancelar o evento #{@event.title}? Ele continua no calendário, riscado."}
        >
          Cancelar evento
        </.button>
        <.button
          :if={@can_manage? and @event.status == :cancelled}
          id="reopen-event"
          variant="outline"
          size="sm"
          phx-click="reopen"
          data-confirm={"Reabrir o evento #{@event.title}?"}
        >
          Reabrir
        </.button>
        <.button
          :if={@full_access?}
          id="delete-event"
          variant="destructive"
          size="sm"
          phx-click="delete"
          data-confirm={"Excluir o evento #{@event.title}? Isto não dá para desfazer."}
        >
          Excluir
        </.button>
      </:actions>

      <.header>
        <span class={@event.status == :cancelled && "line-through"}>{@event.title}</span>
        <:subtitle>
          <.badge variant="secondary">{@event.event_type.name}</.badge>
          <.badge :if={@event.status == :cancelled} id="event-cancelled-badge" variant="outline">
            Cancelado
          </.badge>
        </:subtitle>
      </.header>

      <dl class="divide-border mt-6 divide-y text-sm">
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Data</dt>
          <dd id="event-date" class="text-right font-medium">
            {LocalTime.format(@event.starts_at, :date)}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Hora</dt>
          <dd id="event-time" class="text-right font-medium">
            {LocalTime.format(@event.starts_at, :time)}
          </dd>
        </div>
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Local</dt>
          <dd id="event-location" class="text-right">
            <span :if={@event.location} class="font-medium">{@event.location}</span>
            <span :if={is_nil(@event.location)} class="text-muted-foreground italic">
              Não informado
            </span>
          </dd>
        </div>
      </dl>

      <div class="mt-8">
        <.header>
          Bandas
          <:subtitle>Quem toca neste evento.</:subtitle>
        </.header>

        <ul :if={@event_bands != []} id="event-bands" class="divide-border mt-3 divide-y text-sm">
          <li :for={row <- @event_bands} id={"event-band-#{row.event_band.band_id}"} class="py-3">
            <div class="flex items-center justify-between gap-4">
              <.link
                navigate={~p"/bands/#{row.event_band.band_id}"}
                class="font-medium underline-offset-4 hover:underline"
              >
                {row.event_band.band.name}
              </.link>
              <div class="flex items-center gap-1">
                <span
                  :if={row.set != []}
                  id={"set-count-#{row.event_band.band_id}"}
                  class="text-muted-foreground"
                >
                  {length(row.set)} no set
                </span>
                <.link
                  :if={row.can_manage_set?}
                  id={"manage-set-#{row.event_band.band_id}"}
                  navigate={~p"/events/#{@event.id}/bands/#{row.event_band.band_id}/set"}
                  class={button_variant(%{variant: "outline", size: "sm"})}
                >
                  Montar set
                </.link>
                <.button
                  :if={@full_access?}
                  id={"unschedule-band-#{row.event_band.band_id}"}
                  variant="ghost"
                  size="sm"
                  phx-click="unschedule"
                  phx-value-id={row.event_band.band_id}
                  data-confirm={unschedule_confirm(row)}
                >
                  Desescalar
                </.button>
              </div>
            </div>

            <ul
              id={"event-band-roster-#{row.event_band.band_id}"}
              class="text-muted-foreground mt-2 space-y-1"
            >
              <li
                :for={entry <- row.roster}
                id={"roster-entry-#{row.event_band.band_id}-#{entry.user.id}"}
                class="flex items-center justify-between gap-4"
              >
                <span>
                  <span class="text-foreground font-medium">
                    {(entry.substitute || entry.user).name}
                  </span>
                  <.badge :if={entry.leader? and is_nil(entry.substitute)} class="ml-2">
                    Líder
                  </.badge>
                  <.badge
                    :if={entry.substitute}
                    id={"roster-provisional-#{row.event_band.band_id}-#{entry.user.id}"}
                    variant="outline"
                    class="ml-2"
                  >
                    Provisório
                  </.badge>
                  <span :if={entry.substitute} class="ml-2 text-xs">
                    no lugar de {entry.user.name}
                  </span>
                </span>
                <span class="flex items-center gap-2 text-right">
                  <span :if={entry.member}>{BandMember.role_label(entry.member)}</span>
                  <span :if={is_nil(entry.member)} class="italic">Sem função definida</span>
                  <%!-- O `entry.member &&` é o que tira o botão do líder sem vínculo:
                  sem função não há com o que casar; o `is_nil(entry.substitute)`
                  tira o da vaga que já foi trocada, que não se troca de novo. --%>
                  <.link
                    :if={
                      entry.member && is_nil(entry.substitute) &&
                        MapSet.member?(@requestable, entry.member.id)
                    }
                    id={"request-swap-#{entry.member.id}"}
                    navigate={~p"/events/#{@event.id}/members/#{entry.member.id}/swap"}
                    class={button_variant(%{variant: "outline", size: "sm"})}
                  >
                    Solicitar troca
                  </.link>
                </span>
              </li>
            </ul>

            <ol
              :if={row.set != []}
              id={"event-band-set-#{row.event_band.band_id}"}
              class="divide-border border-border mt-2 divide-y rounded-md border"
            >
              <.set_row
                :for={{item, index} <- Enum.with_index(row.set, 1)}
                item={item}
                index={index}
              />
            </ol>

            <p
              :if={row.set == []}
              id={"event-band-set-empty-#{row.event_band.band_id}"}
              class="text-muted-foreground mt-2"
            >
              Set ainda não montado.
            </p>
          </li>
        </ul>

        <p :if={@event_bands == []} id="event-bands-empty" class="text-muted-foreground mt-3 text-sm">
          Nenhuma banda escalada.
        </p>

        <.form
          :if={@full_access? and @schedulable_bands != []}
          for={@schedule_form}
          id="schedule-band-form"
          phx-submit="schedule"
          class="mt-4 flex items-end gap-2"
        >
          <div class="flex-1">
            <.form_item>
              <.form_label field={@schedule_form[:band_id]}>Escalar banda</.form_label>
              <.select
                field={@schedule_form[:band_id]}
                prompt="Escolha a banda"
                options={Enum.map(@schedulable_bands, &{&1.name, &1.id})}
                required
              />
            </.form_item>
          </div>
          <.button phx-disable-with="Escalando...">Escalar</.button>
        </.form>

        <p
          :if={@full_access? and @schedulable_bands == []}
          id="no-schedulable-bands"
          class="text-muted-foreground mt-4 text-sm"
        >
          Todas as bandas já estão escaladas neste evento.
        </p>
      </div>

      <div :if={@event.notes} class="mt-8">
        <.header>
          Observações
          <:subtitle>O que quem está escalado precisa saber.</:subtitle>
        </.header>
        <p id="event-notes" class="mt-3 text-sm whitespace-pre-line">{@event.notes}</p>
      </div>
    </Layouts.app>
    """
  end
end
