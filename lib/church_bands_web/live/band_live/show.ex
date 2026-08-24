defmodule ChurchBandsWeb.BandLive.Show do
  @moduledoc """
  Detalhe de uma banda (US 1.6): quem lidera, quem toca e o que cada um faz
  ali.

  Leitura é ampla — qualquer usuário logado abre esta página, de qualquer
  banda, mesmo sem poder mudar nada nela. Os botões de editar a banda e de
  mexer no elenco só aparecem para quem responde por ela, e o evento de
  remover reconsulta o contexto antes de agir: esconder o botão nunca é
  autorização.

  O botão **Repertório** é a exceção entre as ações do topo, e por isso não tem
  `:if`: desde a US 2.6 a leitura do repertório é ampla, como a do elenco logo
  abaixo. Ele nasceu condicional na US 2.2, quando aquela tela era só de quem
  monta, e perdeu a condicional junto com a restrição — o que continua restrito
  é *Adicionar música*, lá dentro.

  É aqui que mora o elenco. A tela de integrantes (US 1.4) é só o formulário —
  de adicionar e, desde o DT-9, de corrigir a função de quem já está — e
  devolve para cá depois de salvar: a lista mudando é o retorno visível do que
  se fez.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Bands.get_band(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Banda não encontrada.")
         |> redirect(to: ~p"/bands")}

      band ->
        current_user = socket.assigns.current_user

        {:ok,
         socket
         |> assign(:page_title, band.name)
         |> assign(:band, band)
         |> assign(:can_edit?, Bands.edit_band?(current_user, band))
         |> assign(:can_manage_members?, Bands.manage_members?(current_user, band))
         |> load_roster()}
    end
  end

  @impl true
  def handle_event("remove", %{"id" => id}, socket) do
    member = Bands.get_member(id)
    band = socket.assigns.band

    # Reconsulta a permissão e confere que o vínculo é mesmo desta banda: o id
    # vem do navegador e poderia apontar para o elenco de outra.
    cond do
      not Bands.manage_members?(socket.assigns.current_user, band) ->
        {:noreply, put_flash(socket, :error, "Você não tem permissão para remover integrantes.")}

      is_nil(member) or member.band_id != band.id ->
        {:noreply, socket |> put_flash(:error, "Integrante não encontrado.") |> load_roster()}

      true ->
        {:ok, member} = Bands.remove_member(member)

        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} saiu da #{band.name}.")
         |> load_roster()}
    end
  end

  defp load_roster(socket) do
    roster = Bands.list_roster(socket.assigns.band)

    socket
    |> assign(:roster, roster)
    |> assign(:roster_count, length(roster))
    |> assign(:missing_role?, Enum.any?(roster, &is_nil(&1.member)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      csp_nonce={@csp_nonce}
      breadcrumb={[{"Bandas", ~p"/bands"}, {@band.name, nil}]}
    >
      <:actions>
        <.link
          id="back-to-bands"
          navigate={~p"/bands"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar
        </.link>
        <.link
          :if={@can_edit?}
          id="edit-band"
          navigate={~p"/bands/#{@band.id}/edit"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          Editar banda
        </.link>
        <.link
          id="band-repertoire"
          navigate={~p"/bands/#{@band.id}/repertoire"}
          class={button_variant(%{variant: "outline", size: "sm"})}
        >
          <.icon name="hero-musical-note" class="mr-2 size-4" /> Repertório
        </.link>
        <.link
          :if={@can_manage_members?}
          id="add-member"
          navigate={~p"/bands/#{@band.id}/members/new"}
          class={button_variant(%{size: "sm"})}
        >
          <.icon name="hero-plus" class="mr-2 size-4" /> Adicionar integrante
        </.link>
      </:actions>

      <.header>
        {@band.name}
        <:subtitle>
          {@roster_count} no palco, contando o Líder de Banda.
        </:subtitle>
      </.header>

      <p :if={@band.description} id="band-description" class="text-muted-foreground mt-4">
        {@band.description}
      </p>

      <dl class="divide-border mt-6 divide-y text-sm">
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-muted-foreground">Líder de Banda</dt>
          <dd class="text-right">
            <span class="font-medium">{@band.leader.name}</span>
            <p class="text-muted-foreground">{@band.leader.email}</p>
          </dd>
        </div>
      </dl>

      <div class="mt-10">
        <.header>
          Elenco
          <:subtitle>Quem sobe para tocar e a função de cada um nesta banda.</:subtitle>
        </.header>

        <.alert
          :if={@missing_role? and @can_manage_members?}
          id="leader-without-role"
          class="mt-4"
        >
          <.icon name="hero-exclamation-triangle" class="size-4" />
          <.alert_description>
            O Líder de Banda também toca ou canta na apresentação, e ainda está sem função aqui.
            Use <strong>Adicionar integrante</strong> para definir o instrumento ou o naipe dele.
          </.alert_description>
        </.alert>

        <.table id="members" rows={@roster}>
          <:col :let={entry} label="Músico">
            <span class="font-medium">{entry.user.name}</span>
            <.badge :if={entry.leader?} class="ml-2">Líder</.badge>
            <p class="text-muted-foreground text-sm">{entry.user.email}</p>
          </:col>
          <:col :let={entry} label="Função">
            <span :if={entry.member}>{BandMember.role_label(entry.member)}</span>
            <span :if={is_nil(entry.member)} class="text-muted-foreground text-sm italic">
              Sem função definida
            </span>
          </:col>
          <:action :let={entry} :if={@can_manage_members?}>
            <.link
              :if={entry.member}
              id={"edit-member-#{entry.member.id}"}
              navigate={~p"/bands/#{@band.id}/members/#{entry.member.id}/edit"}
              class={button_variant(%{variant: "outline", size: "sm"})}
            >
              Editar
            </.link>
            <.button
              :if={entry.member}
              id={"remove-member-#{entry.member.id}"}
              variant="destructive"
              size="sm"
              phx-click="remove"
              phx-value-id={entry.member.id}
              data-confirm={"Remover #{entry.user.name} da #{@band.name}?"}
            >
              Remover
            </.button>
          </:action>
        </.table>
      </div>
    </Layouts.app>
    """
  end
end
