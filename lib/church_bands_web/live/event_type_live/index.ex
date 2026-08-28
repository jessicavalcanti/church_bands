defmodule ChurchBandsWeb.EventTypeLive.Index do
  @moduledoc """
  Tipos de evento do calendário (US 3.1) — restrita a Pastor e Líder de Louvor
  pelo hook `:ensure_full_access` declarado na `live_session` do router.

  É o vocabulário do que a igreja marca na agenda, e é daqui que sai o campo
  *Tipo* do evento (US 3.2). Fechar a lista num enum resolveria metade — a
  outra metade é a "Vigília" que a igreja resolve fazer, que não pode depender
  de deploy.

  Cada tipo carrega a marcação **Líder de Banda pode criar**. Nesta tela ela só
  se grava e se exibe; quem a lê é a criação de evento pelo Líder de Banda
  (US 3.4). Ela é do tipo e não do evento — desmarcar "Ensaio" amanhã não
  desfaz o ensaio marcado ontem.

  **Cadastrar e corrigir são o mesmo formulário**, num card inline na própria
  lista, alternado pelo `live_action` com `push_patch` — o padrão de
  `InstrumentLive.Index` e `TagLive.Index`, não um modal.

  A tela não reconfere permissão nos eventos: ela é de acesso total inteira e
  não abre para leitura ampla, então o hook da rota é a autorização. Reconferir
  seria um `if` que nenhum caminho alcança.
  """
  use ChurchBandsWeb, :live_view

  import ChurchBandsWeb.Components.UI.Checkbox

  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.EventType

  @impl true
  def mount(_params, _session, socket) do
    # `editing` nasce aqui, e não só no `apply_action/3`: o `:edit` com id
    # inválido devolve para a lista sem passar pelo ramo que o atribuiria, e o
    # breadcrumb leria um assign que não existe.
    {:ok,
     socket
     |> assign(:editing, nil)
     |> load_event_types()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tipos de evento")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Schedule.change_event_type()))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Novo tipo de evento")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Schedule.change_event_type()))
  end

  # O id vem da URL e pode ser qualquer coisa — inclusive o de um tipo que
  # outra pessoa acabou de excluir. Voltar para a lista com o recado é melhor
  # do que abrir um formulário vazio que não salvaria nada.
  defp apply_action(socket, :edit, params) do
    case Schedule.get_event_type(params["id"]) do
      nil ->
        socket
        |> put_flash(:error, "Tipo de evento não encontrado.")
        |> push_patch(to: ~p"/event-types")

      event_type ->
        socket
        |> assign(:page_title, "Editar #{event_type.name}")
        |> assign(:editing, event_type)
        |> assign(:form, to_form(Schedule.change_event_type(event_type)))
    end
  end

  @impl true
  def handle_event("validate", %{"event_type" => params}, socket) do
    changeset = Schedule.change_event_type(socket.assigns.editing || %EventType{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"event_type" => params}, socket) do
    save_event_type(socket, socket.assigns.editing, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    event_type = Schedule.get_event_type(id)

    case event_type && Schedule.delete_event_type(event_type) do
      {:ok, event_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tipo de evento #{event_type.name} excluído.")
         |> assign(:event_types_count, socket.assigns.event_types_count - 1)
         |> stream_delete(:event_types, event_type)}

      # Quem marcou eventos com o tipo não é problema de quem digitou o nome: a
      # recusa é da lista, não do campo, e por isso volta como flash — o mesmo
      # caminho da tag em uso (US 2.7).
      {:error, {:in_use, count}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "O tipo #{event_type.name} não dá para excluir: #{existem(count)} " <>
             "deste tipo. Mude o tipo desses eventos antes de excluí-lo."
         )}

      _ ->
        {:noreply, refresh_stale(socket)}
    end
  end

  defp save_event_type(socket, nil, params) do
    case Schedule.create_event_type(params) do
      {:ok, event_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tipo de evento #{event_type.name} cadastrado.")
         |> load_event_types()
         |> push_patch(to: ~p"/event-types")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_event_type(socket, %EventType{} = event_type, params) do
    case Schedule.update_event_type(event_type, params) do
      {:ok, event_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tipo de evento #{event_type.name} atualizado.")
         |> load_event_types()
         |> push_patch(to: ~p"/event-types")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # Cadastrar e renomear mudam a **posição** da linha, porque a lista é
  # alfabética — aí quem está velho é a lista inteira, e recarregá-la é o
  # certo. Excluir mexe numa linha só, e o stream dá conta.
  defp load_event_types(socket) do
    event_types = Schedule.list_event_types()

    socket
    |> assign(:event_types_count, length(event_types))
    |> stream(:event_types, event_types, reset: true)
  end

  # A tela mostrava um tipo que não existe mais: provavelmente não é a única
  # diferença, e a lista inteira se refaz.
  defp refresh_stale(socket) do
    socket
    |> put_flash(:error, "Tipo de evento não encontrado.")
    |> load_event_types()
  end

  defp events_label(1), do: "1 evento"
  defp events_label(count), do: "#{count} eventos"

  # O verbo concorda com a contagem: "existe 1 evento", "existem 12 eventos".
  defp existem(1), do: "existe 1 evento"
  defp existem(count), do: "existem #{events_label(count)}"

  defp event_count_label(0), do: "Nenhum evento"
  defp event_count_label(count), do: events_label(count)

  # A trilha do formulário depende de estar cadastrando ou corrigindo: ao
  # corrigir, o último nível é o tipo de que se fala.
  defp breadcrumb(:new, _editing),
    do: [{"Tipos de evento", ~p"/event-types"}, {"Novo tipo", nil}]

  defp breadcrumb(:edit, %EventType{} = event_type),
    do: [{"Tipos de evento", ~p"/event-types"}, {event_type.name, nil}]

  defp breadcrumb(_action, _editing), do: [{"Tipos de evento", nil}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={breadcrumb(@live_action, @editing)}
    >
      <:actions>
        <.link
          :if={@live_action == :index}
          id="new-event-type-button"
          patch={~p"/event-types/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Novo tipo de evento
        </.link>
      </:actions>

      <.header>
        Tipos de evento
        <:subtitle>
          O que a igreja marca na agenda — culto, ensaio, o que fizer sentido aqui. Cadastre o
          tipo antes de marcar o primeiro evento dele no calendário. Tipo já usado por algum
          evento não pode ser excluído.
        </:subtitle>
      </.header>

      <.card :if={@live_action != :index} id="event-type-form-card" class="my-4">
        <.card_content class="pt-6">
          <.form
            for={@form}
            id="event-type-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <.form_item>
              <.form_label field={@form[:name]}>Nome do tipo</.form_label>
              <.input field={@form[:name]} type="text" placeholder="Vigília" required />
              <.form_message field={@form[:name]} />
            </.form_item>

            <.form_item>
              <div class="flex items-center gap-2">
                <.checkbox field={@form[:band_leader_can_create]} />
                <.form_label field={@form[:band_leader_can_create]}>
                  Líder de Banda pode criar evento deste tipo
                </.form_label>
              </div>
              <.form_description>
                Marque para que o líder possa marcar ensaio da própria banda.
              </.form_description>
            </.form_item>

            <div class="flex gap-2">
              <.button phx-disable-with="Salvando...">
                {if @editing, do: "Salvar tipo", else: "Cadastrar tipo"}
              </.button>
              <.link
                id="cancel-event-type-form"
                patch={~p"/event-types"}
                class={button_variant(%{variant: "outline"})}
              >
                Cancelar
              </.link>
            </div>
          </.form>
        </.card_content>
      </.card>

      <div
        :if={@event_types_count == 0}
        id="event-types-empty"
        class="text-muted-foreground py-8 text-center"
      >
        Nenhum tipo de evento cadastrado.
      </div>

      <.table :if={@event_types_count > 0} id="event-types" rows={@streams.event_types}>
        <:col :let={{_id, event_type}} label="Tipo">
          <span class="font-medium">{event_type.name}</span>
        </:col>
        <:col :let={{_id, event_type}} label="Em quantos eventos">
          <span id={"event-type-events-#{event_type.id}"}>
            {event_count_label(event_type.event_count)}
          </span>
        </:col>
        <:col :let={{_id, event_type}} label="Quem pode criar">
          <.badge
            :if={event_type.band_leader_can_create}
            id={"event-type-band-leader-#{event_type.id}"}
            variant="default"
          >
            Líder pode criar
          </.badge>
          <span
            :if={not event_type.band_leader_can_create}
            id={"event-type-full-access-#{event_type.id}"}
            class="text-muted-foreground"
          >
            Só acesso total
          </span>
        </:col>
        <:action :let={{_id, event_type}}>
          <.link
            id={"edit-event-type-#{event_type.id}"}
            patch={~p"/event-types/#{event_type.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, event_type}}>
          <.button
            id={"delete-event-type-#{event_type.id}"}
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={event_type.id}
            data-confirm={"Excluir o tipo #{event_type.name}?"}
          >
            Excluir
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
