defmodule ChurchBandsWeb.BandLive.Form do
  @moduledoc """
  Formulário de cadastro e edição de banda (US 1.3).

  A autorização é feita na `live_session` do router, antes do mount: `/bands/new`
  exige Pastor ou Líder de Louvor (`:ensure_full_access`) e `/bands/:id/edit`
  exige, além deles, que o Líder da Banda possa editar a própria banda
  (`:ensure_band_editor`, que também carrega `@band`).
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Band

  @impl true
  def mount(_params, _session, socket) do
    band = socket.assigns[:band] || %Band{}

    {:ok,
     socket
     |> assign(:band, band)
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:leader_options, leader_options())
     |> assign(:form, to_form(Bands.change_band(band)))}
  end

  @impl true
  def handle_event("validate", %{"band" => params}, socket) do
    changeset = Bands.change_band(socket.assigns.band, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"band" => params}, socket) do
    save_band(socket, socket.assigns.live_action, params)
  end

  defp save_band(socket, :new, params) do
    case Bands.create_band(params) do
      {:ok, band} ->
        {:noreply,
         socket
         |> put_flash(:info, "Banda #{band.name} cadastrada.")
         |> push_navigate(to: ~p"/bands")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_band(socket, :edit, params) do
    case Bands.update_band(socket.assigns.band, params) do
      {:ok, band} ->
        {:noreply,
         socket
         |> put_flash(:info, "Banda #{band.name} atualizada.")
         |> push_navigate(to: ~p"/bands")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # Só quem já ativou a conta pode liderar uma banda (US 1.2): quem ainda não
  # entrou no sistema não teria como cuidar dela.
  defp leader_options do
    Enum.map(Bands.list_leader_candidates(), &{&1.name, &1.id})
  end

  defp page_title(:new), do: "Nova banda"
  defp page_title(:edit), do: "Editar banda"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@page_title}
        <:subtitle>
          Toda banda precisa de um Líder de Banda designado entre os usuários ativos.
        </:subtitle>
      </.header>

      <.form for={@form} id="band-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Nome da banda" required />

        <.input
          field={@form[:leader_id]}
          type="select"
          label="Líder de Banda"
          prompt="Escolha o líder"
          options={@leader_options}
          required
        />

        <.input
          field={@form[:description]}
          type="textarea"
          label="Descrição"
          placeholder="Opcional — quando a banda toca, estilo, observações."
        />

        <div class="flex gap-2 mt-4">
          <.button variant="primary" phx-disable-with="Salvando...">
            {if @live_action == :new, do: "Cadastrar banda", else: "Salvar alterações"}
          </.button>
          <.button id="cancel-band-form" navigate={~p"/bands"}>Cancelar</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
