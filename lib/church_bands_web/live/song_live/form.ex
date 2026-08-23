defmodule ChurchBandsWeb.SongLive.Form do
  @moduledoc """
  Cadastro e edição de música do catálogo (US 2.1).

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_full_access`): só Pastor e Líder de Louvor cuidam do catálogo.

  **O aviso de música parecida é o coração desta tela.** Título repetido não é
  bloqueado — não existe índice único em `title` —, então, enquanto o título é
  digitado, o bloco abaixo do campo mostra o que já existe com nome parecido,
  cada uma com link para o próprio cadastro em nova aba. Quem digita confere
  sem perder o que escreveu, e salva assim mesmo se for outra música: dois
  arranjos do mesmo hino existem, e recusar o segundo seria pior do que ter os
  dois.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Repertoire
  alias ChurchBands.Repertoire.Song

  @impl true
  def mount(params, _session, socket) do
    mount_action(socket, socket.assigns.live_action, params)
  end

  defp mount_action(socket, :new, _params) do
    {:ok, mount_song(socket, %Song{})}
  end

  defp mount_action(socket, :edit, params) do
    case Repertoire.get_song(params["id"]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Música não encontrada.")
         |> push_navigate(to: ~p"/songs")}

      song ->
        {:ok, mount_song(socket, song)}
    end
  end

  # O aviso de parecidas já vale na abertura da tela de edição, com o título
  # que está gravado — é ali que se descobre que a música foi cadastrada duas
  # vezes. No cadastro o título ainda é `nil`, e a consulta devolve vazio pelo
  # mínimo de caracteres.
  defp mount_song(socket, %Song{} = song) do
    socket
    |> assign(:song, song)
    |> assign(:page_title, page_title(socket.assigns.live_action))
    |> assign(:form, to_form(Repertoire.change_song(song)))
    |> assign_similar_songs(to_string(song.title))
  end

  @impl true
  def handle_event("validate", %{"song" => params}, socket) do
    changeset = Repertoire.change_song(socket.assigns.song, params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign_similar_songs(params["title"])}
  end

  def handle_event("save", %{"song" => params}, socket) do
    save_song(socket, socket.assigns.live_action, params)
  end

  defp save_song(socket, :new, params) do
    case Repertoire.create_song(params) do
      {:ok, song} ->
        {:noreply,
         socket
         |> put_flash(:info, "Música #{song.title} cadastrada.")
         |> push_navigate(to: ~p"/songs")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_song(socket, :edit, params) do
    case Repertoire.update_song(socket.assigns.song, params) do
      {:ok, song} ->
        {:noreply,
         socket
         |> put_flash(:info, "Música #{song.title} atualizada.")
         |> push_navigate(to: ~p"/songs")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # A música em edição não é parecida consigo mesma: o id dela sai do
  # resultado. No cadastro ele é `nil`, e nada é excluído.
  defp assign_similar_songs(socket, title) do
    similar = Repertoire.find_similar_songs(title, socket.assigns.song.id)

    assign(socket, :similar_songs, similar)
  end

  defp page_title(:new), do: "Nova música"
  defp page_title(:edit), do: "Editar música"

  defp breadcrumb(:new, _song), do: [{"Músicas", ~p"/songs"}, {"Nova música", nil}]
  defp breadcrumb(:edit, song), do: [{"Músicas", ~p"/songs"}, {song.title, nil}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={breadcrumb(@live_action, @song)}
    >
      <.header>
        {@page_title}
        <:subtitle>
          Só o título é obrigatório. O resto se preenche quando a informação aparecer.
        </:subtitle>
      </.header>

      <.form for={@form} id="song-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.form_item>
          <.form_label field={@form[:title]}>Título</.form_label>
          <.input field={@form[:title]} type="text" phx-debounce="300" required />
          <.form_message field={@form[:title]} />

          <div
            :if={@similar_songs != []}
            id="similar-songs"
            class="border-border bg-muted/40 mt-2 rounded-md border p-3"
          >
            <p class="text-sm font-medium">Músicas parecidas já cadastradas</p>
            <p class="text-muted-foreground text-sm">
              Confira se não é a mesma. Você pode salvar mesmo assim.
            </p>
            <ul class="mt-2 space-y-1">
              <li :for={song <- @similar_songs} class="text-sm">
                <.link
                  id={"similar-song-#{song.id}"}
                  href={~p"/songs/#{song.id}/edit"}
                  target="_blank"
                  rel="noopener"
                  class="font-medium underline-offset-4 hover:underline"
                >
                  {song.title}
                </.link>
                <span :if={song.artist} class="text-muted-foreground">— {song.artist}</span>
              </li>
            </ul>
          </div>
        </.form_item>

        <.form_item>
          <.form_label field={@form[:artist]}>Artista</.form_label>
          <.input field={@form[:artist]} type="text" placeholder="Opcional" />
          <.form_message field={@form[:artist]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:bpm]}>BPM</.form_label>
          <.input field={@form[:bpm]} type="number" placeholder="Opcional — o andamento da música" />
          <.form_message field={@form[:bpm]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:reference_url]}>Link de referência</.form_label>
          <.input field={@form[:reference_url]} type="text" placeholder="https://..." />
          <.form_message field={@form[:reference_url]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:chord_chart_url]}>Link da cifra</.form_label>
          <.input field={@form[:chord_chart_url]} type="text" placeholder="https://..." />
          <.form_message field={@form[:chord_chart_url]} />
        </.form_item>

        <div class="flex gap-2 pt-2">
          <.button phx-disable-with="Salvando...">
            {if @live_action == :new, do: "Cadastrar música", else: "Salvar alterações"}
          </.button>
          <.link
            id="cancel-song-form"
            navigate={~p"/songs"}
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
