defmodule ChurchBandsWeb.InviteLive.Index do
  @moduledoc """
  Tela de convites (US 1.1) — restrita a Pastor e Líder de Louvor pelo hook
  `:ensure_full_access` declarado na `live_session` do router.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.Invite

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Convites")
     |> assign(:form, to_form(Accounts.change_invite()))
     |> load_invites()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :showing_form?, socket.assigns.live_action == :new)}
  end

  @impl true
  def handle_event("validate", %{"invite" => params}, socket) do
    changeset = Accounts.change_invite(%Invite{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"invite" => params}, socket) do
    case Accounts.create_invite(params, socket.assigns.current_user) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Convite enviado para #{invite.email}.")
         |> assign(:form, to_form(Accounts.change_invite()))
         |> load_invites()
         |> push_patch(to: ~p"/admin/invites")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}

      {:error, {:delivery_failed, _reason}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Não foi possível enviar o e-mail do convite. Tente novamente.")
         |> load_invites()}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    invite = Accounts.get_invite(id)

    case invite && Accounts.resend_invite(invite) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Convite reenviado para #{invite.email}.")
         |> load_invites()}

      {:error, :already_accepted} ->
        {:noreply,
         socket
         |> put_flash(:error, "Este convite já foi aceito e não pode ser reenviado.")
         |> load_invites()}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível reenviar o convite.")}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    invite = Accounts.get_invite(id)

    case invite && Accounts.cancel_invite(invite) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Convite para #{invite.email} cancelado.")
         |> load_invites()}

      {:error, :already_accepted} ->
        {:noreply,
         socket
         |> put_flash(:error, "Este convite já foi aceito e não pode ser cancelado.")
         |> load_invites()}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível cancelar o convite.")}
    end
  end

  defp load_invites(socket) do
    invites = Accounts.list_invites()

    socket
    |> assign(:invites_count, length(invites))
    |> stream(:invites, invites, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Convites
        <:subtitle>
          Convide novas pessoas para o sistema. O convite vale por {Invite.validity_in_days()} dias.
        </:subtitle>
        <:actions>
          <.button
            :if={not @showing_form?}
            id="new-invite-button"
            patch={~p"/admin/invites/new"}
            variant="primary"
          >
            <.icon name="hero-plus" /> Novo convite
          </.button>
        </:actions>
      </.header>

      <div :if={@showing_form?} id="invite-form-card" class="card bg-base-200 p-4 my-4">
        <.form for={@form} id="invite-form" phx-change="validate" phx-submit="save">
          <.input
            field={@form[:email]}
            type="email"
            label="E-mail da pessoa convidada"
            placeholder="nome@exemplo.com"
            required
          />
          <div class="flex gap-2 mt-4">
            <.button variant="primary" phx-disable-with="Enviando...">Enviar convite</.button>
            <.button id="cancel-invite-form" patch={~p"/admin/invites"}>Cancelar</.button>
          </div>
        </.form>
      </div>

      <div :if={@invites_count == 0} id="invites-empty" class="text-base-content/60 py-8 text-center">
        Nenhum convite enviado ainda.
      </div>

      <.table :if={@invites_count > 0} id="invites" rows={@streams.invites}>
        <:col :let={{_id, invite}} label="E-mail">{invite.email}</:col>
        <:col :let={{_id, invite}} label="Status">
          <span class={["badge", status_class(invite.status)]}>{status_label(invite.status)}</span>
        </:col>
        <:col :let={{_id, invite}} label="Expira em">{format_date(invite.expires_at)}</:col>
        <:col :let={{_id, invite}} label="Convidado por">{invite.invited_by.name}</:col>
        <:action :let={{_id, invite}}>
          <.button
            :if={invite.status != :accepted}
            id={"resend-invite-#{invite.id}"}
            phx-click="resend"
            phx-value-id={invite.id}
          >
            Reenviar
          </.button>
        </:action>
        <:action :let={{_id, invite}}>
          <.button
            :if={invite.status not in [:accepted, :cancelled]}
            id={"cancel-invite-#{invite.id}"}
            phx-click="cancel"
            phx-value-id={invite.id}
            data-confirm="Cancelar este convite?"
          >
            Cancelar
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  defp status_label(:pending), do: "Pendente"
  defp status_label(:accepted), do: "Aceito"
  defp status_label(:expired), do: "Expirado"
  defp status_label(:cancelled), do: "Cancelado"

  defp status_class(:pending), do: "badge-warning"
  defp status_class(:accepted), do: "badge-success"
  defp status_class(:expired), do: "badge-neutral"
  defp status_class(:cancelled), do: "badge-ghost"

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y")
  end
end
