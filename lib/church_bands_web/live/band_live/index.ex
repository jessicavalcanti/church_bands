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

      is_nil(band) ->
        {:noreply, socket |> put_flash(:error, "Banda não encontrada.") |> load_bands()}

      true ->
        {:ok, band} = Bands.delete_band(band)

        {:noreply,
         socket
         |> put_flash(:info, "Banda #{band.name} excluída.")
         |> load_bands()}
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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Bandas
        <:subtitle>
          As bandas do grupo de louvor. Abra uma delas para ver quem toca ali.
        </:subtitle>
        <:actions>
          <.button :if={@can_manage?} id="new-band-button" navigate={~p"/bands/new"} variant="primary">
            <.icon name="hero-plus" /> Nova banda
          </.button>
        </:actions>
      </.header>

      <div :if={@bands_count == 0} id="bands-empty" class="text-base-content/60 py-8 text-center">
        Nenhuma banda cadastrada ainda.
      </div>

      <.table :if={@bands_count > 0} id="bands" rows={@streams.bands}>
        <:col :let={{_id, band}} label="Banda">
          <.link id={"band-#{band.id}"} navigate={~p"/bands/#{band.id}"} class="font-medium link">
            {band.name}
          </.link>
          <p :if={band.description} class="text-sm text-base-content/60">{band.description}</p>
        </:col>
        <:col :let={{_id, band}} label="Líder de Banda">{band.leader.name}</:col>
        <:col :let={{_id, band}} label="Integrantes">
          <span id={"band-roster-count-#{band.id}"}>{band.roster_count}</span>
        </:col>
        <:action :let={{_id, band}}>
          <.button
            :if={editable?(@current_user, band)}
            id={"edit-band-#{band.id}"}
            navigate={~p"/bands/#{band.id}/edit"}
          >
            Editar
          </.button>
        </:action>
        <:action :let={{_id, band}}>
          <.button
            :if={@can_manage?}
            id={"delete-band-#{band.id}"}
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
