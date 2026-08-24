defmodule ChurchBandsWeb.EventLive.Form do
  @moduledoc """
  Marcar e corrigir um evento da agenda (US 3.2) — restrita a Pastor e Líder de
  Louvor pelo hook `:ensure_full_access` da `live_session`.

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

  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event

  @impl true
  def mount(params, _session, socket) do
    mount_action(socket, socket.assigns.live_action, params)
  end

  defp mount_action(socket, :new, _params) do
    {:ok, mount_event(socket, %Event{})}
  end

  # O id vem da URL e pode apontar para um evento que já foi excluído — ou não
  # ser id nenhum. Voltar para a agenda com o recado é melhor do que abrir um
  # formulário que não salvaria nada.
  defp mount_action(socket, :edit, params) do
    case Schedule.get_event(params["id"]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Evento não encontrado.")
         |> push_navigate(to: ~p"/calendar")}

      event ->
        {:ok, mount_event(socket, event)}
    end
  end

  defp mount_event(socket, %Event{} = event) do
    socket
    |> assign(:event, event)
    |> assign(:page_title, page_title(socket.assigns.live_action))
    |> assign(:type_options, type_options())
    |> assign(:form, to_form(Schedule.change_event(event)))
  end

  defp type_options do
    Enum.map(Schedule.list_event_types(), &{&1.name, &1.id})
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset = Schedule.change_event(socket.assigns.event, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"event" => params}, socket) do
    save_event(socket, socket.assigns.live_action, params)
  end

  defp save_event(socket, :new, params) do
    case Schedule.create_event(params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento #{event.title} criado.")
         |> push_navigate(to: ~p"/events/#{event.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_event(socket, :edit, params) do
    case Schedule.update_event(socket.assigns.event, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Evento #{event.title} atualizado.")
         |> push_navigate(to: ~p"/events/#{event.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

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
