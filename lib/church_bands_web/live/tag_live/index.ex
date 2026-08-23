defmodule ChurchBandsWeb.TagLive.Index do
  @moduledoc """
  Tags temáticas das músicas (US 2.7) — restrita a Pastor e Líder de Louvor
  pelo hook `:ensure_full_access` declarado na `live_session` do router.

  É o vocabulário do grupo: em que momento do culto a música entra, de que
  época ela é. Cadastrar aqui é o que permite marcar no formulário de música, e
  é por isso que a tela **não** oferece criar tag por lá — a tag criada de
  dentro de um formulário que acaba não salvando fica órfã no catálogo.

  **Cadastrar e renomear são o mesmo formulário**, num card inline na própria
  lista, alternado pelo `live_action` com `push_patch` — o padrão de
  `InviteLive.Index` e `InstrumentLive.Index`, não um modal.

  A tela não reconfere permissão nos eventos: ela é de acesso total inteira e
  não abre para leitura ampla, então o hook da rota é a autorização. Reconferir
  seria um `if` que nenhum caminho alcança.

  Sem item próprio no menu lateral: a porta de entrada é o botão **Gerenciar
  tags** em `/songs`, que é de onde alguém sente falta de uma tag.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.Tag

  @impl true
  def mount(_params, _session, socket) do
    # `editing` nasce aqui, e não só no `apply_action/3`: o `:edit` com id
    # inválido devolve para a lista sem passar pelo ramo que o atribuiria, e o
    # breadcrumb leria um assign que não existe.
    {:ok,
     socket
     |> assign(:editing, nil)
     |> load_tags()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tags")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Repertoire.change_tag()))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Nova tag")
    |> assign(:editing, nil)
    |> assign(:form, to_form(Repertoire.change_tag()))
  end

  # O id vem da URL e pode ser qualquer coisa — inclusive o de uma tag que
  # outra pessoa acabou de excluir. Voltar para a lista com o recado é melhor
  # do que abrir um formulário vazio que não salvaria nada.
  defp apply_action(socket, :edit, params) do
    case Repertoire.get_tag(params["id"]) do
      nil ->
        socket
        |> put_flash(:error, "Tag não encontrada.")
        |> push_patch(to: ~p"/admin/tags")

      tag ->
        socket
        |> assign(:page_title, "Renomear #{tag.name}")
        |> assign(:editing, tag)
        |> assign(:form, to_form(Repertoire.change_tag(tag)))
    end
  end

  @impl true
  def handle_event("validate", %{"tag" => params}, socket) do
    changeset = Repertoire.change_tag(socket.assigns.editing || %Tag{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"tag" => params}, socket) do
    save_tag(socket, socket.assigns.editing, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tag = Repertoire.get_tag(id)

    case tag && Repertoire.delete_tag(tag) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag #{tag.name} excluída.")
         |> assign(:tags_count, socket.assigns.tags_count - 1)
         |> stream_delete(:tags, tag)}

      # Quem marcou a tag nas músicas não é problema de quem digitou o nome: a
      # recusa é da lista, não do campo, e por isso volta como flash.
      {:error, {:in_use, count}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A tag #{tag.name} está em #{songs_label(count)}. " <>
             "Desmarque a tag nessas músicas antes de excluí-la."
         )}

      _ ->
        {:noreply, refresh_stale(socket)}
    end
  end

  defp save_tag(socket, nil, params) do
    case Repertoire.create_tag(params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag #{tag.name} cadastrada.")
         |> load_tags()
         |> push_patch(to: ~p"/admin/tags")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_tag(socket, %Tag{} = tag, params) do
    case Repertoire.update_tag(tag, params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag #{tag.name} atualizada.")
         |> load_tags()
         |> push_patch(to: ~p"/admin/tags")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # Cadastrar e renomear mudam a **posição** da linha, porque a lista é
  # alfabética — aí quem está velho é a lista inteira, e recarregá-la é o
  # certo. Excluir mexe numa linha só, e o stream dá conta.
  defp load_tags(socket) do
    tags = Repertoire.list_tags()

    socket
    |> assign(:tags_count, length(tags))
    |> stream(:tags, tags, reset: true)
  end

  # A tela mostrava uma tag que não existe mais: provavelmente não é a única
  # diferença, e a lista inteira se refaz.
  defp refresh_stale(socket) do
    socket
    |> put_flash(:error, "Tag não encontrada.")
    |> load_tags()
  end

  defp songs_label(1), do: "1 música"
  defp songs_label(count), do: "#{count} músicas"

  defp song_count_label(0), do: "Nenhuma música"
  defp song_count_label(count), do: songs_label(count)

  # A trilha nasce em *Músicas*, e não em *Início*: as tags existem para o
  # catálogo, e é de lá que se chega aqui.
  defp breadcrumb(:new, _editing),
    do: [{"Músicas", ~p"/songs"}, {"Tags", ~p"/admin/tags"}, {"Nova tag", nil}]

  defp breadcrumb(:edit, %Tag{} = tag),
    do: [{"Músicas", ~p"/songs"}, {"Tags", ~p"/admin/tags"}, {tag.name, nil}]

  defp breadcrumb(_action, _editing), do: [{"Músicas", ~p"/songs"}, {"Tags", nil}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={breadcrumb(@live_action, @editing)}
    >
      <:actions>
        <.link
          :if={@live_action == :index}
          id="new-tag-button"
          patch={~p"/admin/tags/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Nova tag
        </.link>
      </:actions>

      <.header>
        Tags
        <:subtitle>
          O vocabulário do grupo para marcar as músicas — momento do culto, época do ano, o que
          fizer sentido aqui. Cadastre a tag antes de marcá-la nas músicas.
        </:subtitle>
      </.header>

      <.card :if={@live_action != :index} id="tag-form-card" class="my-4">
        <.card_content class="pt-6">
          <.form for={@form} id="tag-form" phx-change="validate" phx-submit="save" class="space-y-4">
            <.form_item>
              <.form_label field={@form[:name]}>Nome da tag</.form_label>
              <.input field={@form[:name]} type="text" placeholder="Ministração" required />
              <.form_message field={@form[:name]} />
            </.form_item>

            <div class="flex gap-2">
              <.button phx-disable-with="Salvando...">
                {if @editing, do: "Salvar tag", else: "Cadastrar tag"}
              </.button>
              <.link
                id="cancel-tag-form"
                patch={~p"/admin/tags"}
                class={button_variant(%{variant: "outline"})}
              >
                Cancelar
              </.link>
            </div>
          </.form>
        </.card_content>
      </.card>

      <div :if={@tags_count == 0} id="tags-empty" class="text-muted-foreground py-8 text-center">
        Nenhuma tag cadastrada ainda.
      </div>

      <.table :if={@tags_count > 0} id="tags" rows={@streams.tags}>
        <:col :let={{_id, tag}} label="Tag">
          <.badge id={"tag-badge-#{tag.id}"} variant="secondary">{tag.name}</.badge>
        </:col>
        <:col :let={{_id, tag}} label="Em quantas músicas">
          <span id={"tag-songs-#{tag.id}"}>{song_count_label(tag.song_count)}</span>
        </:col>
        <:action :let={{_id, tag}}>
          <.link
            id={"edit-tag-#{tag.id}"}
            patch={~p"/admin/tags/#{tag.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, tag}}>
          <.button
            id={"delete-tag-#{tag.id}"}
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={tag.id}
            data-confirm={"Excluir a tag #{tag.name}?"}
          >
            Excluir
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
