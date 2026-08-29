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

  # A trilha do formulário depende de estar cadastrando ou editando: no
  # cadastro a banda ainda não existe, e no editar ela é um nível a mais, com o
  # nome que veio do dado carregado.
  defp breadcrumb(:new, _band), do: [{"Bandas", ~p"/bands"}, {"Nova banda", nil}]

  defp breadcrumb(:edit, band),
    do: [{"Bandas", ~p"/bands"}, {band.name, ~p"/bands/#{band.id}"}, {"Editar", nil}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={breadcrumb(@live_action, @band)}
    >
      <.header>
        {@page_title}
        <:subtitle>
          Toda banda precisa de um Líder de Banda designado entre os usuários ativos.
        </:subtitle>
      </.header>

      <.form for={@form} id="band-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.form_item>
          <.form_label field={@form[:name]}>Nome da banda</.form_label>
          <.input field={@form[:name]} type="text" required />
          <.form_message field={@form[:name]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:leader_id]}>Líder de Banda</.form_label>
          <.select
            field={@form[:leader_id]}
            prompt="Escolha o líder"
            options={@leader_options}
            required
          />
          <.form_message field={@form[:leader_id]} />
        </.form_item>

        <.form_item>
          <.form_label field={@form[:description]}>Descrição</.form_label>
          <.textarea
            field={@form[:description]}
            placeholder="Opcional — quando a banda toca, estilo, observações."
          />
          <.form_message field={@form[:description]} />
        </.form_item>

        <div class="flex gap-2 pt-2">
          <.button phx-disable-with="Salvando...">
            {if @live_action == :new, do: "Cadastrar banda", else: "Salvar alterações"}
          </.button>
          <.link
            id="cancel-band-form"
            navigate={~p"/bands"}
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
