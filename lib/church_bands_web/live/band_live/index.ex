defmodule ChurchBandsWeb.BandLive.Index do
  @moduledoc """
  Lista das bandas cadastradas — ponto de entrada do cadastro de banda
  (US 1.3).

  Leitura é ampla: qualquer usuário logado vê a lista. Os botões de cadastrar
  e excluir só aparecem para Pastor e Líder de Louvor, e o de editar também
  para o Líder da própria banda — mas a decisão real está em
  `ChurchBands.Bands`, consultado de novo antes de excluir.

  O nome de cada banda leva ao detalhe dela (US 1.6), que é por onde qualquer
  um vê o elenco e por onde quem responde pela banda chega à tela de
  integrantes (US 1.4).
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bandas")
     |> assign(:can_manage?, Bands.manage_bands?(socket.assigns.current_user))
     |> load_bands()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    band = Bands.get_band(id)

    # Reconsulta a permissão: esconder o botão na tela não é autorização.
    cond do
      not Bands.manage_bands?(socket.assigns.current_user) ->
        {:noreply, put_flash(socket, :error, "Você não tem permissão para excluir bandas.")}

      # Aqui a lista inteira está velha, e não uma linha só: quem sumiu do banco
      # ainda está na tela, e provavelmente não é a única diferença.
      is_nil(band) ->
        {:noreply, socket |> put_flash(:error, "Banda não encontrada.") |> load_bands()}

      true ->
        {:ok, band} = Bands.delete_band(band)

        # Só uma linha saiu: tirar essa linha é o que o stream existe para
        # fazer. Recarregar a coleção toda para apagar uma delas devolvia o
        # banco inteiro e re-renderizava a tabela.
        {:noreply,
         socket
         |> put_flash(:info, "Banda #{band.name} excluída.")
         |> assign(:bands_count, socket.assigns.bands_count - 1)
         |> stream_delete(:bands, band)}
    end
  end

  defp load_bands(socket) do
    bands = Bands.list_bands()

    socket
    |> assign(:bands_count, length(bands))
    |> stream(:bands, bands, reset: true)
  end

  defp editable?(current_user, band), do: Bands.edit_band?(current_user, band)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={[{"Bandas", nil}]}
    >
      <:actions>
        <.link
          :if={@can_manage?}
          id="new-band-button"
          navigate={~p"/bands/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Nova banda
        </.link>
      </:actions>

      <.header>
        Bandas
        <:subtitle>
          As bandas do grupo de louvor. Abra uma delas para ver quem toca ali.
        </:subtitle>
      </.header>

      <div :if={@bands_count == 0} id="bands-empty" class="text-muted-foreground py-8 text-center">
        Nenhuma banda cadastrada ainda.
      </div>

      <.table :if={@bands_count > 0} id="bands" rows={@streams.bands}>
        <:col :let={{_id, band}} label="Banda">
          <.link
            id={"band-#{band.id}"}
            navigate={~p"/bands/#{band.id}"}
            class="font-medium underline-offset-4 hover:underline"
          >
            {band.name}
          </.link>
          <p :if={band.description} class="text-muted-foreground text-sm">{band.description}</p>
        </:col>
        <:col :let={{_id, band}} label="Líder de Banda">{band.leader.name}</:col>
        <:col :let={{_id, band}} label="Integrantes">
          <span id={"band-roster-count-#{band.id}"}>{band.roster_count}</span>
        </:col>
        <:action :let={{_id, band}}>
          <.link
            :if={editable?(@current_user, band)}
            id={"edit-band-#{band.id}"}
            navigate={~p"/bands/#{band.id}/edit"}
            class={button_variant(%{variant: "outline", size: "sm"})}
          >
            Editar
          </.link>
        </:action>
        <:action :let={{_id, band}}>
          <.button
            :if={@can_manage?}
            id={"delete-band-#{band.id}"}
            variant="destructive"
            size="sm"
            phx-click="delete"
            phx-value-id={band.id}
            data-confirm={"Excluir a banda #{band.name}?"}
          >
            Excluir
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
