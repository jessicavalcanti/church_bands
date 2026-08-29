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
         |> stream_insert(:invites, invite)}

      # A tela mostrava esse convite como pendente e ele já estava aceito: o
      # que está velho é aquela linha, e é ela que se corrige.
      {:error, :already_accepted} ->
        {:noreply,
         socket
         |> put_flash(:error, "Este convite já foi aceito e não pode ser reenviado.")
         |> stream_insert(:invites, invite)}

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
         |> stream_insert(:invites, invite)}

      {:error, :already_accepted} ->
        {:noreply,
         socket
         |> put_flash(:error, "Este convite já foi aceito e não pode ser cancelado.")
         |> stream_insert(:invites, invite)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível cancelar o convite.")}
    end
  end

  # Reenviar e cancelar mudam **uma** linha, e `stream_insert/3` a atualiza no
  # lugar. Criar não: `create_invite/2` passa por `expire_overdue_invites/0`,
  # que pode mudar o status de outros convites da tela — aí a lista inteira
  # mudou de verdade, e recarregá-la é o certo.
  defp load_invites(socket) do
    invites = Accounts.list_invites()

    socket
    |> assign(:invites_count, length(invites))
    |> stream(:invites, invites, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      unread={@unread_notifications}
      breadcrumb={breadcrumb(@live_action)}
    >
      <:actions>
        <.link
          :if={not @showing_form?}
          id="new-invite-button"
          patch={~p"/admin/invites/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Novo convite
        </.link>
      </:actions>

      <.header>
        Convites
        <:subtitle>
          Convide novas pessoas para o sistema. O convite vale por {Invite.validity_in_days()} dias.
        </:subtitle>
      </.header>

      <.card :if={@showing_form?} id="invite-form-card" class="my-4">
        <.card_content class="pt-6">
          <.form
            for={@form}
            id="invite-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <.form_item>
              <.form_label field={@form[:email]}>E-mail da pessoa convidada</.form_label>
              <.input
                field={@form[:email]}
                type="email"
                placeholder="nome@exemplo.com"
                required
              />
              <.form_message field={@form[:email]} />
            </.form_item>

            <div class="flex gap-2">
              <.button phx-disable-with="Enviando...">Enviar convite</.button>
              <.link
                id="cancel-invite-form"
                patch={~p"/admin/invites"}
                class={button_variant(%{variant: "outline"})}
              >
                Cancelar
              </.link>
            </div>
          </.form>
        </.card_content>
      </.card>

      <div
        :if={@invites_count == 0}
        id="invites-empty"
        class="text-muted-foreground py-8 text-center"
      >
        Nenhum convite enviado ainda.
      </div>

      <.table :if={@invites_count > 0} id="invites" rows={@streams.invites}>
        <:col :let={{_id, invite}} label="E-mail">{invite.email}</:col>
        <:col :let={{_id, invite}} label="Status">
          <.badge variant={status_variant(invite.status)}>{status_label(invite.status)}</.badge>
        </:col>
        <:col :let={{_id, invite}} label="Expira em">{format_date(invite.expires_at)}</:col>
        <:col :let={{_id, invite}} label="Convidado por">{invite.invited_by.name}</:col>
        <:action :let={{_id, invite}}>
          <.button
            :if={invite.status != :accepted}
            id={"resend-invite-#{invite.id}"}
            variant="outline"
            size="sm"
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
            variant="destructive"
            size="sm"
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

  # O sistema é preto e branco: o status não vira cor, vira peso. Só o
  # cancelado usa o vermelho, que é a cor semântica que sobrou.
  defp status_variant(:pending), do: "default"
  defp status_variant(:accepted), do: "secondary"
  defp status_variant(:expired), do: "outline"
  defp status_variant(:cancelled), do: "destructive"

  defp breadcrumb(:new), do: [{"Convites", ~p"/admin/invites"}, {"Novo convite", nil}]
  defp breadcrumb(_), do: [{"Convites", nil}]

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y")
  end
end
