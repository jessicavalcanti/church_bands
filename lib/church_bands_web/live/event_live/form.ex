defmodule ChurchBandsWeb.EventLive.Form do
  @moduledoc """
  Marcar e corrigir um evento da agenda.

  **Duas pessoas diferentes chegam aqui (US 3.4)**, e por isso são dois hooks e
  duas `live_session`s: `:ensure_event_creator` guarda `/events/new`, e
  `:ensure_event_manager` guarda `/events/:id/edit` e já entrega o evento em
  `@event`.

  Quem tem acesso total marca qualquer tipo e escala as bandas depois, na tela
  do evento. O **Líder de Banda** marca só os tipos marcados com
  `band_leader_can_create`, e o evento dele nasce com a banda já escalada, na
  mesma transação — sem isso o ensaio ficaria sem dono no instante seguinte ao
  de ser criado.

  **O seletor de tipo mostra só o que a pessoa pode marcar**, nas duas ações. Na
  edição isso é o que impede o líder de trocar o tipo do próprio ensaio por um
  que ele não gerencia e se trancar do lado de fora. O seletor esconde; quem
  recusa de verdade é `Schedule.create_event_of_type?/2`, no contexto — um
  changeset não conhece quem está gravando.

  **O campo de data e hora é o virtual `starts_at_local`**, e não o `starts_at`
  do banco. O banco guarda UTC; ligar o `datetime-local` direto nele mostraria
  a hora do servidor, e cada `phx-change` reconverteria o valor já convertido,
  deslocando o horário a cada tecla. Quem converte é o changeset, uma vez só —
  a LiveView não sabe o que é fuso.

  **A recusa de data no passado cai no campo**, e não num flash: é erro de
  preenchimento, e quem digitou o ano errado precisa ver a mensagem ao lado do
  que digitou. A recusa vale só ao criar — `Schedule.change_event/2` escolhe o
  changeset pelo evento ser novo ou não, e corrigir um culto de semana passada
  continua permitido.

  O tipo vem da lista da US 3.1, e não se cadastra por aqui: quem inventa
  "Vigília" vai a *Tipos de evento*, como quem inventa tag vai a *Tags*.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event

  @impl true
  def mount(params, _session, socket) do
    mount_action(socket, socket.assigns.live_action, params)
  end

  defp mount_action(socket, :new, _params) do
    {:ok, mount_event(socket, %Event{})}
  end

  # O evento vem do hook `:ensure_event_manager`, que já recusou o id que não
  # existe — e é o mesmo hook que recusa quem não gerencia aquele evento.
  defp mount_action(socket, :edit, _params) do
    {:ok, mount_event(socket, socket.assigns.event)}
  end

  defp mount_event(socket, %Event{} = event) do
    socket
    |> assign(:event, event)
    |> assign(:page_title, page_title(socket.assigns.live_action))
    |> assign(:type_options, type_options(socket.assigns.full_access?))
    |> assign_leading_bands()
    |> assign(:form, to_form(Schedule.change_event(event)))
  end

  defp type_options(full_access?) do
    Schedule.list_event_types()
    |> Enum.filter(&(full_access? or &1.band_leader_can_create))
    |> Enum.map(&{&1.name, &1.id})
  end

  # As bandas que a pessoa lidera só interessam a quem cria sem acesso total:
  # é o evento **novo** que nasce com banda escalada. Quem tem acesso total
  # escala depois, na tela do evento, onde a escala inteira mora — e a edição
  # não mexe em escala nenhuma.
  defp assign_leading_bands(socket) do
    bands =
      if socket.assigns.live_action == :new and not socket.assigns.full_access? do
        Bands.list_led_bands(socket.assigns.current_user)
      else
        []
      end

    socket
    |> assign(:leading_bands, bands)
    |> assign(:single_band, single(bands))
  end

  # Quem lidera uma banda só não tem escolha a fazer: ela vai num campo
  # escondido, e a tela apenas diz qual é. Oferecer um seletor de uma opção
  # seria pedir uma decisão que não existe.
  defp single([band]), do: band
  defp single(_bands), do: nil

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset = Schedule.change_event(socket.assigns.event, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"event" => params}, socket) do
    save_event(socket, socket.assigns.live_action, params)
  end

  defp save_event(socket, :new, params) do
    case create_event(socket, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento #{event.title} criado.")
         |> push_navigate(to: ~p"/events/#{event.id}")}

      {:error, reason} ->
        {:noreply,
         assign(socket, :form, to_form(refused(socket, params, reason), action: :insert))}
    end
  end

  defp save_event(socket, :edit, params) do
    case Schedule.update_event(socket.assigns.event, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento #{event.title} atualizado.")
         |> push_navigate(to: ~p"/events/#{event.id}")}

      {:error, reason} ->
        {:noreply,
         assign(socket, :form, to_form(refused(socket, params, reason), action: :update))}
    end
  end

  # Quem tem acesso total marca o evento sozinho e escala as bandas depois; o
  # Líder de Banda marca o evento e a escala juntos, ou nenhum dos dois.
  defp create_event(%{assigns: %{full_access?: true}}, params), do: Schedule.create_event(params)

  defp create_event(socket, params),
    do: Schedule.create_event_with_band(params, socket.assigns.current_user)

  # **Toda recusa cai num campo, e nunca num flash.** As de changeset já vêm
  # penduradas; as três que o contexto devolve como átomo ou tupla são
  # penduradas aqui, cada uma no campo de que fala — o tipo que a pessoa não
  # pode marcar no seletor de tipo, a banda no seletor de banda, e o choque de
  # horário na data, que é o campo que ela precisa corrigir.
  defp refused(_socket, _params, %Ecto.Changeset{} = changeset), do: changeset

  defp refused(socket, params, reason) do
    changeset = Schedule.change_event(socket.assigns.event, params)

    case reason do
      :unauthorized_type ->
        Ecto.Changeset.add_error(
          changeset,
          :event_type_id,
          "escolha um tipo que você pode marcar"
        )

      :unauthorized_band ->
        Ecto.Changeset.add_error(changeset, :band_id, "escolha uma banda que você lidera")

      # A criação devolve o conflito sem a banda, porque quem chamou a escolheu
      # e já a tem na mão: é o `band_id` que o formulário mandou, e ele passou
      # pela conferência de liderança antes de chegar aqui.
      {:conflict, event} ->
        band = Bands.get_band(to_string(params["band_id"]))

        Ecto.Changeset.add_error(changeset, :starts_at_local, conflict_message(band.name, event))

      {:conflict, band, event} ->
        Ecto.Changeset.add_error(changeset, :starts_at_local, conflict_message(band.name, event))
    end
  end

  # Minúscula e sem ponto final porque é mensagem de campo, ao lado do que a
  # pessoa digitou, e não frase de flash.
  defp conflict_message(band, event),
    do: "#{band} já está escalada em #{event.title}, no mesmo horário"

  defp page_title(:new), do: "Novo evento"
  defp page_title(:edit), do: "Editar evento"

  defp breadcrumb(:new, _event),
    do: [{"Calendário", ~p"/calendar"}, {"Novo evento", nil}]

  defp breadcrumb(:edit, %Event{} = event),
    do: [
      {"Calendário", ~p"/calendar"},
      {event.title, ~p"/events/#{event.id}"},
      {"Editar", nil}
    ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={breadcrumb(@live_action, @event)}
    >
      <.header>
        {@page_title}
        <:subtitle>
          Tipo, título e quando. Local e observações se preenchem se houver o que dizer.
        </:subtitle>
      </.header>

      <.form for={@form} id="event-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.form_item>
          <div class="flex items-center justify-between">
            <.form_label field={@form[:event_type_id]}>Tipo</.form_label>
            <.link
              :if={@full_access?}
              id="manage-event-types-link"
              navigate={~p"/event-types"}
              class="text-muted-foreground hover:text-foreground text-sm underline-offset-4 hover:underline"
            >
              Gerenciar tipos
            </.link>
          </div>
          <.select
            field={@form[:event_type_id]}
            prompt="Escolha o tipo"
            options={@type_options}
            required
          />
          <.form_message field={@form[:event_type_id]} />
        </.form_item>

        <.form_item :if={@leading_bands != []}>
          <.form_label field={@form[:band_id]}>Banda</.form_label>
          <div :if={@single_band}>
            <input type="hidden" name={@form[:band_id].name} value={@single_band.id} />
            <p id="single-leading-band" class="text-sm font-medium">{@single_band.name}</p>
          </div>
          <.select
            :if={is_nil(@single_band)}
            field={@form[:band_id]}
            prompt="Escolha a banda"
            options={Enum.map(@leading_bands, &{&1.name, &1.id})}
            required
          />
          <.form_message field={@form[:band_id]} />
          <p class="text-muted-foreground text-xs">
            Ela entra escalada junto com o evento.
          </p>
        </.form_item>

        <.form_item>
          <.form_label field={@form[:title]}>Título</.form_label>
          <.input field={@form[:title]} type="text" placeholder="Culto da Noite" required />
          <.form_message field={@form[:title]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:starts_at_local]}>Data e hora</.form_label>
          <.input field={@form[:starts_at_local]} type="datetime-local" required />
          <.form_message field={@form[:starts_at_local]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:location]}>Local</.form_label>
          <.input field={@form[:location]} type="text" placeholder="Opcional — Templo sede" />
          <.form_message field={@form[:location]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:notes]}>Observações</.form_label>
          <.textarea
            field={@form[:notes]}
            rows="4"
            placeholder="Opcional — o que quem está escalado precisa saber"
          />
          <.form_message field={@form[:notes]} />
        </.form_item>

        <div class="flex gap-2 pt-2">
          <.button phx-disable-with="Salvando...">
            {if @live_action == :new, do: "Criar evento", else: "Salvar alterações"}
          </.button>
          <.link
            id="cancel-event-form"
            navigate={~p"/calendar"}
            class={button_variant(%{variant: "outline"})}
          >
            Cancelar
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
