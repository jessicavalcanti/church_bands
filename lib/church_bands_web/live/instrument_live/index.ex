defmodule ChurchBandsWeb.InstrumentLive.Index do
  @moduledoc """
  Catálogo de instrumentos do grupo de louvor (US 2.8) — restrito a Pastor e
  Líder de Louvor pelo hook `:ensure_full_access` declarado na `live_session`
  do router.

  É daqui que sai o dropdown de *Instrumento* do formulário de integrante. A
  US 1.4 deixava aquele campo como texto livre com sugestões, e sugestão não
  obriga nada: "Bateria", "Baterista" e "Batera" viravam três instrumentos.
  Fechar a lista sem esta tela resolveria metade — a outra metade é o
  instrumento que a igreja adquire depois, que não pode depender de deploy.

  **Cadastrar e corrigir são o mesmo formulário**, num card inline na própria
  lista, alternado pelo `live_action` com `push_patch` — o padrão de
  `InviteLive.Index`, não um modal.

  A tela não reconfere permissão nos eventos, e isso é decisão: ela é de acesso
  total inteira e não abre para leitura ampla, então o hook da rota é a
  autorização. Reconferir seria um `if` que nenhum caminho alcança. Onde a tela
  é aberta e a ação é inline — remover integrante em `BandLive.Show` —, a
  reconferência continua obrigatória.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Instrument

  @impl true
  def mount(_params, _session, socket) do
    # `editing` nasce aqui, e não só no `apply_action/3`: o `:edit` com id
    # inválido devolve para a lista sem passar pelo ramo que o atribuiria, e o
    # breadcrumb leria um assign que não existe.
    {:ok,
     socket
     |> assign(:editing, nil)
     |> load_instruments()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Instrumentos")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Bands.change_instrument()))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Novo instrumento")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Bands.change_instrument()))
  end

  # O id vem da URL e pode ser qualquer coisa — inclusive o de um instrumento
  # que outra pessoa acabou de excluir. Voltar para a lista com o recado é
  # melhor do que abrir um formulário vazio que não salvaria nada.
  defp apply_action(socket, :edit, params) do
    case Bands.get_instrument(params["id"]) do
      nil ->
        socket
        |> put_flash(:error, "Instrumento não encontrado.")
        |> push_patch(to: ~p"/instruments")

      instrument ->
        socket
        |> assign(:page_title, "Corrigir #{instrument.name}")
        |> assign(:editing, instrument)
        |> assign(:form, to_form(Bands.change_instrument(instrument)))
    end
  end

  @impl true
  def handle_event("validate", %{"instrument" => params}, socket) do
    changeset = Bands.change_instrument(socket.assigns.editing || %Instrument{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"instrument" => params}, socket) do
    save_instrument(socket, socket.assigns.editing, params)
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    instrument = Bands.get_instrument(id)

    case instrument && Bands.set_instrument_active(instrument, not instrument.active) do
      {:ok, instrument} ->
        {:noreply,
         socket
         |> put_flash(:info, "Instrumento #{instrument.name} #{active_label(instrument)}.")
         |> insert_row(instrument)}

      _ ->
        {:noreply, refresh_stale(socket, "Instrumento não encontrado.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    instrument = Bands.get_instrument(id)

    case instrument && Bands.delete_instrument(instrument) do
      {:ok, instrument} ->
        {:noreply,
         socket
         |> put_flash(:info, "Instrumento #{instrument.name} excluído.")
         |> assign(:instruments_count, socket.assigns.instruments_count - 1)
         |> assign(:member_counts, Map.delete(socket.assigns.member_counts, instrument.id))
         |> stream_delete(:instruments, instrument)}

      # Quem toca o instrumento não é problema de quem digitou o nome: a recusa
      # é da lista, não do campo, e por isso volta como flash.
      {:error, {:in_use, count}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{instrument.name} é tocado por #{members_label(count)}. " <>
             "Desative o instrumento em vez de excluí-lo."
         )}

      _ ->
        {:noreply, refresh_stale(socket, "Instrumento não encontrado.")}
    end
  end

  defp save_instrument(socket, nil, params) do
    case Bands.create_instrument(params) do
      {:ok, instrument} ->
        {:noreply,
         socket
         |> put_flash(:info, "Instrumento #{instrument.name} cadastrado.")
         |> load_instruments()
         |> push_patch(to: ~p"/instruments")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_instrument(socket, %Instrument{} = instrument, params) do
    case Bands.update_instrument(instrument, params) do
      {:ok, instrument} ->
        {:noreply,
         socket
         |> put_flash(:info, "Instrumento #{instrument.name} atualizado.")
         |> load_instruments()
         |> push_patch(to: ~p"/instruments")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # Cadastrar e renomear mudam a **posição** da linha, porque a lista é
  # alfabética — aí quem está velho é a lista inteira, e recarregá-la é o
  # certo. Desativar e excluir mexem numa linha só, e o stream dá conta.
  defp load_instruments(socket) do
    instruments = Bands.list_instruments()

    socket
    |> assign(:instruments_count, length(instruments))
    |> assign(:member_counts, Map.new(instruments, &{&1.id, &1.member_count}))
    |> stream(:instruments, instruments, reset: true)
  end

  # `member_count` é virtual: o struct que volta do banco depois de ativar ou
  # desativar não o traz, e a linha mostraria "Ninguém" para um instrumento
  # tocado por três pessoas. Desativar não muda quem toca, então a contagem que
  # a lista já tinha continua valendo.
  defp insert_row(socket, %Instrument{} = instrument) do
    count = Map.get(socket.assigns.member_counts, instrument.id, 0)
    stream_insert(socket, :instruments, %{instrument | member_count: count})
  end

  # A tela mostrava um instrumento que não existe mais: provavelmente não é a
  # única diferença, e a lista inteira se refaz.
  defp refresh_stale(socket, message) do
    socket
    |> put_flash(:error, message)
    |> load_instruments()
  end

  defp active_label(%Instrument{active: true}), do: "reativado"
  defp active_label(%Instrument{active: false}), do: "desativado"

  defp members_label(1), do: "1 integrante"
  defp members_label(count), do: "#{count} integrantes"

  defp member_count_label(0), do: "Ninguém"
  defp member_count_label(count), do: members_label(count)

  # A trilha do formulário depende de estar cadastrando ou corrigindo: ao
  # corrigir, o último nível é o instrumento de que se fala.
  defp breadcrumb(:new, _editing),
    do: [{"Instrumentos", ~p"/instruments"}, {"Novo instrumento", nil}]

  defp breadcrumb(:edit, %Instrument{} = instrument),
    do: [{"Instrumentos", ~p"/instruments"}, {instrument.name, nil}]

  defp breadcrumb(_action, _editing), do: [{"Instrumentos", nil}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={breadcrumb(@live_action, @editing)}
    >
      <:actions>
        <.link
          :if={@live_action == :index}
          id="new-instrument-button"
          patch={~p"/instruments/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Novo instrumento
        </.link>
      </:actions>

      <.header>
        Instrumentos
        <:subtitle>
          Os instrumentos que o grupo de louvor toca. É desta lista que sai a função de cada
          instrumentista — cadastre aqui o instrumento novo antes de escalar quem vai tocá-lo.
        </:subtitle>
      </.header>

      <.card :if={@live_action != :index} id="instrument-form-card" class="my-4">
        <.card_content class="pt-6">
          <.form
            for={@form}
            id="instrument-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <.form_item>
              <.form_label field={@form[:name]}>Nome do instrumento</.form_label>
              <.input field={@form[:name]} type="text" placeholder="Cavaquinho" required />
              <.form_message field={@form[:name]} />
            </.form_item>

            <div class="flex gap-2">
              <.button phx-disable-with="Salvando...">
                {if @editing, do: "Salvar instrumento", else: "Cadastrar instrumento"}
              </.button>
              <.link
                id="cancel-instrument-form"
                patch={~p"/instruments"}
                class={button_variant(%{variant: "outline"})}
              >
                Cancelar
              </.link>
            </div>
          </.form>
        </.card_content>
      </.card>

      <div
        :if={@instruments_count == 0}
        id="instruments-empty"
        class="text-muted-foreground py-8 text-center"
      >
        Nenhum instrumento cadastrado ainda.
      </div>

      <.table :if={@instruments_count > 0} id="instruments" rows={@streams.instruments}>
        <:col :let={{_id, instrument}} label="Instrumento">
          <span class="font-medium">{instrument.name}</span>
        </:col>
        <:col :let={{_id, instrument}} label="Situação">
          <.badge id={"instrument-status-#{instrument.id}"} variant={status_variant(instrument)}>
            {if instrument.active, do: "Ativo", else: "Inativo"}
          </.badge>
        </:col>
        <:col :let={{_id, instrument}} label="Quem toca">
          <span id={"instrument-members-#{instrument.id}"}>
            {member_count_label(instrument.member_count)}
          </span>
        </:col>
        <:action :let={{_id, instrument}}>
          <.link
            id={"edit-instrument-#{instrument.id}"}
            patch={~p"/instruments/#{instrument.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, instrument}}>
          <.button
            id={"toggle-instrument-#{instrument.id}"}
            variant="outline"
            size="sm"
            phx-click="toggle_active"
            phx-value-id={instrument.id}
          >
            {if instrument.active, do: "Desativar", else: "Ativar"}
          </.button>
        </:action>
        <:action :let={{_id, instrument}}>
          <.button
            id={"delete-instrument-#{instrument.id}"}
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={instrument.id}
            data-confirm={"Excluir o instrumento #{instrument.name}?"}
          >
            Excluir
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  # O sistema é preto e branco: inativo não vira cor, vira peso — o mesmo
  # tratamento que os status de convite recebem.
  defp status_variant(%Instrument{active: true}), do: "default"
  defp status_variant(%Instrument{active: false}), do: "outline"
end
