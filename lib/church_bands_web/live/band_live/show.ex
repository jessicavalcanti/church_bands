defmodule ChurchBandsWeb.BandLive.Show do
  @moduledoc """
  Detalhe de uma banda (US 1.6): quem lidera, quem toca e o que cada um faz
  ali.

  Leitura é ampla — qualquer usuário logado abre esta página, de qualquer
  banda, mesmo sem poder mudar nada nela. Os botões de editar a banda e de
  mexer no elenco só aparecem para quem responde por ela, e o evento de
  remover reconsulta o contexto antes de agir: esconder o botão nunca é
  autorização.

  É aqui que mora o elenco. A tela de integrantes (US 1.4) ficou sendo só o
  formulário de adicionar e devolve para cá depois de vincular alguém — a
  lista crescendo é o retorno visível de ter adicionado.
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

  defp role_label(%BandMember{type: :instrumentalist} = member), do: member.instrument
  defp role_label(%BandMember{type: :vocalist} = member), do: "Vocal — #{member.voice_part}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@band.name}
        <:subtitle>
          {@roster_count} no palco, contando o Líder de Banda.
        </:subtitle>
        <:actions>
          <.button id="back-to-bands" navigate={~p"/bands"}>Voltar</.button>
          <.button :if={@can_edit?} id="edit-band" navigate={~p"/bands/#{@band.id}/edit"}>
            Editar banda
          </.button>
          <.button
            :if={@can_manage_members?}
            id="add-member"
            navigate={~p"/bands/#{@band.id}/members/new"}
            variant="primary"
          >
            <.icon name="hero-plus" /> Adicionar integrante
          </.button>
        </:actions>
      </.header>

      <p :if={@band.description} id="band-description" class="mt-4 text-base-content/70">
        {@band.description}
      </p>

      <dl class="mt-6 divide-y divide-base-300 text-sm">
        <div class="flex justify-between gap-4 py-3">
          <dt class="text-base-content/60">Líder de Banda</dt>
          <dd class="text-right">
            <span class="font-medium">{@band.leader.name}</span>
            <p class="text-base-content/60">{@band.leader.email}</p>
          </dd>
        </div>
      </dl>

      <div class="mt-10">
        <.header>
          Elenco
          <:subtitle>Quem sobe para tocar e a função de cada um nesta banda.</:subtitle>
        </.header>

        <div
          :if={@missing_role? and @can_manage_members?}
          id="leader-without-role"
          class="mt-4 rounded-lg border border-warning/40 bg-warning/10 px-4 py-3 text-sm"
        >
          O Líder de Banda também toca ou canta na apresentação, e ainda está sem função aqui.
          Use <strong>Adicionar integrante</strong> para definir o instrumento ou o naipe dele.
        </div>

        <.table id="members" rows={@roster}>
          <:col :let={entry} label="Músico">
            <span class="font-medium">{entry.user.name}</span>
            <span :if={entry.leader?} class="badge badge-primary badge-sm ml-2">Líder</span>
            <p class="text-sm text-base-content/60">{entry.user.email}</p>
          </:col>
          <:col :let={entry} label="Função">
            <span :if={entry.member}>{role_label(entry.member)}</span>
            <span :if={is_nil(entry.member)} class="text-sm text-base-content/60 italic">
              Sem função definida
            </span>
          </:col>
          <:action :let={entry} :if={@can_manage_members?}>
            <.button
              :if={entry.member}
              id={"remove-member-#{entry.member.id}"}
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
