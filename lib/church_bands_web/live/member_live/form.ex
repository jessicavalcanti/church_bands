defmodule ChurchBandsWeb.MemberLive.Form do
  @moduledoc """
  Integrantes de uma banda (US 1.4): adiciona um músico já existente no sistema
  ao elenco da banda, com a função que ele exerce ali — e corrige essa função
  depois, sem desfazer o vínculo (DT-9).

  A autorização acontece na `live_session` do router, antes do mount
  (`:ensure_band_member_manager`, que também carrega `@band`): Líder da própria
  banda, Pastor ou Líder de Louvor. A remoção reconsulta o contexto antes de
  agir — esconder o botão nunca é autorização.

  **Adicionar e corrigir são a mesma tela porque são o mesmo formulário**, com
  uma diferença que vale dizer: ao corrigir, o músico não é escolhível. Trocar
  de pessoa não é corrigir uma função — seria remover uma e adicionar outra —,
  então o dropdown dá lugar ao nome de quem já está no elenco, e o contexto
  reafirma músico e banda a partir do próprio vínculo.

  **O instrumento vem do catálogo** (US 2.8), não de um campo de texto: a US 1.4
  deixava digitar qualquer coisa aqui, e "Bateria", "Baterista" e "Batera"
  entravam como três instrumentos. Agora é um dropdown, como o naipe do
  vocalista ao lado. Instrumento novo se cadastra em `/instruments`, que é de
  acesso total — o Líder de Banda escolhe da lista e pede quando falta algum, e
  o recado abaixo do campo diz isso em vez de deixá-lo procurando um botão que
  não existe.

  O campo de músico é um dropdown de quem pode entrar, com uma busca ao lado
  que apenas o estreita: a lista completa serve para escolher olhando, e a
  busca serve para quem já sabe o nome. Quem já é integrante desta banda fica
  de fora das duas; quem toca em outra banda continua disponível.

  O elenco mora na página de detalhe da banda (`/bands/:id`, US 1.6), e é para
  lá que esta tela devolve depois de vincular alguém ou de corrigir a função: a
  lista mudando é o retorno visível do que se fez. Remover um integrante também
  acontece lá, ao lado do nome dele.
  """
  use ChurchBandsWeb, :live_view

  alias ChurchBands.Accounts
  alias ChurchBands.Bands
  alias ChurchBands.Bands.BandMember

  @impl true
  def mount(params, _session, socket) do
    mount_action(socket, socket.assigns.live_action, params)
  end

  defp mount_action(socket, :new, _params) do
    {:ok,
     socket
     |> assign(:member, %BandMember{})
     |> assign(:page_title, "Adicionar integrante à #{socket.assigns.band.name}")
     |> assign(:form, to_form(Bands.change_member()))
     |> assign_instrument_options(nil)
     |> load_candidates("")}
  end

  # O `member_id` vem da URL e pode apontar para o elenco de outra banda, ou
  # para um vínculo que já foi desfeito. A permissão da `live_session` responde
  # por *esta* banda, então conferir que o vínculo é mesmo dela faz parte da
  # autorização, não é zelo extra.
  defp mount_action(socket, :edit, params) do
    band = socket.assigns.band
    member = Bands.get_member(params["member_id"])

    if member && member.band_id == band.id do
      {:ok,
       socket
       |> assign(:member, member)
       |> assign(:page_title, "Corrigir a função de #{member.user.name}")
       |> assign(:form, to_form(Bands.change_member(member)))
       |> assign_instrument_options(member.instrument)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Integrante não encontrado.")
       |> push_navigate(to: ~p"/bands/#{band.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"band_member" => params} = payload, socket) do
    changeset = Bands.change_member(socket.assigns.member, params)
    socket = assign(socket, :form, to_form(changeset, action: :validate))

    case socket.assigns.live_action do
      :new -> {:noreply, maybe_load_candidates(socket, Map.get(payload, "search", ""))}
      :edit -> {:noreply, socket}
    end
  end

  def handle_event("save", %{"band_member" => params}, socket) do
    save_member(socket, socket.assigns.live_action, params)
  end

  defp save_member(socket, :new, params) do
    band = socket.assigns.band
    {user_id, attrs} = Map.pop(params, "user_id")

    case Bands.add_member(band, user_id, attrs) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.name} entrou na #{band.name}.")
         |> push_navigate(to: ~p"/bands/#{band.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  defp save_member(socket, :edit, params) do
    band = socket.assigns.band

    case Bands.update_member(socket.assigns.member, params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "Função de #{member.user.name} atualizada.")
         |> push_navigate(to: ~p"/bands/#{band.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  # O instrumento que a pessoa já toca entra na lista mesmo desativado, e é por
  # isso que `list_active_instruments/1` recebe um argumento: sem ele, abrir a
  # correção de quem toca um instrumento aposentado e salvar trocaria a função
  # dela sem que ninguém tivesse pedido.
  defp assign_instrument_options(socket, current) do
    options = Enum.map(Bands.list_active_instruments(current), &{&1.name, &1.id})
    assign(socket, :instrument_options, options)
  end

  # Quem pode entrar na banda não depende do resto do formulário: trocar de
  # instrumentista para vocalista, ou escolher o instrumento, refazia a consulta
  # de candidatos sem nada ter mudado nela. Só o texto da busca a refaz.
  defp maybe_load_candidates(socket, search) do
    if search == socket.assigns.search,
      do: socket,
      else: load_candidates(socket, search)
  end

  # A busca não escolhe ninguém: ela só estreita o dropdown. Quem já está
  # selecionado continua na lista mesmo que deixe de casar com o texto — senão
  # digitar depois de escolher apagaria a escolha.
  defp load_candidates(socket, search) do
    candidates = Bands.list_member_candidates(socket.assigns.band, search)
    selected = selected_user(socket, candidates)

    socket
    |> assign(:search, search)
    |> assign(:candidates, candidates)
    |> assign(:musician_options, musician_options(candidates, selected))
  end

  defp selected_user(socket, candidates) do
    case socket.assigns.form[:user_id].value do
      nil ->
        nil

      "" ->
        nil

      id ->
        id = to_string(id)

        # Fora do filtro, a pessoa é buscada pelo id. Antes isso era um
        # `list_member_candidates/1` sem busca — a lista inteira de candidatos
        # vinda do banco, a cada tecla digitada, para achar **uma** pessoa.
        Enum.find(candidates, &(to_string(&1.id) == id)) || Accounts.get_user(id)
    end
  end

  defp musician_options(candidates, selected) do
    candidates
    |> maybe_prepend(selected)
    |> Enum.map(&{"#{&1.name} — #{&1.email}", &1.id})
  end

  defp maybe_prepend(candidates, nil), do: candidates

  defp maybe_prepend(candidates, selected) do
    if Enum.any?(candidates, &(&1.id == selected.id)),
      do: candidates,
      else: [selected | candidates]
  end

  defp selected_type(form) do
    case form[:type].value do
      value when value in [:instrumentalist, "instrumentalist"] -> :instrumentalist
      value when value in [:vocalist, "vocalist"] -> :vocalist
      _ -> nil
    end
  end

  # A trilha depende de estar adicionando ou corrigindo: ao corrigir, o último
  # nível é a pessoa de quem se fala, não a ação.
  defp breadcrumb(:new, band, _member) do
    [{"Bandas", ~p"/bands"}, {band.name, ~p"/bands/#{band.id}"}, {"Adicionar integrante", nil}]
  end

  defp breadcrumb(:edit, band, member) do
    [{"Bandas", ~p"/bands"}, {band.name, ~p"/bands/#{band.id}"}, {member.user.name, nil}]
  end

  defp submit_label(:new), do: "Adicionar à banda"
  defp submit_label(:edit), do: "Salvar função"

  defp submitting_label(:new), do: "Adicionando..."
  defp submitting_label(:edit), do: "Salvando..."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      sidebar_state={@sidebar_state}
      breadcrumb={breadcrumb(@live_action, @band, @member)}
    >
      <:actions>
        <.link
          id="back-to-band"
          navigate={~p"/bands/#{@band.id}"}
          class={button_variant(%{variant: "ghost", size: "sm"})}
        >
          Voltar para a banda
        </.link>
      </:actions>

      <.header>
        {@page_title}
        <:subtitle>
          {if @live_action == :new,
            do: "Escolha um músico com conta ativa e defina a função dele nesta banda.",
            else: "Troque o instrumento ou o naipe sem desfazer o vínculo com a banda."}
        </:subtitle>
      </.header>

      <.form for={@form} id="member-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.form_item :if={@live_action == :new}>
          <.form_label for="member-search">Filtrar a lista</.form_label>
          <.input
            type="text"
            name="search"
            id="member-search"
            value={@search}
            placeholder="Nome ou e-mail"
            autocomplete="off"
            phx-debounce="300"
          />
        </.form_item>

        <.form_item :if={@live_action == :new}>
          <.form_label field={@form[:user_id]}>Músico</.form_label>
          <.select field={@form[:user_id]} prompt="Escolha o músico" options={@musician_options} />
          <.form_message field={@form[:user_id]} />

          <p :if={@musician_options == []} id="no-candidates" class="text-muted-foreground text-sm">
            {if String.trim(@search) == "",
              do: "Todo mundo com conta ativa já está nesta banda.",
              else: "Nenhum músico disponível com esse nome ou e-mail."} A lista só traz contas já ativas que ainda não são integrantes daqui — quem toca em
            outra banda continua disponível.
          </p>
        </.form_item>

        <div
          :if={@live_action == :edit}
          id="member-identity"
          class="border-border rounded-md border p-4"
        >
          <p class="text-muted-foreground text-sm">Músico</p>
          <p class="font-medium">{@member.user.name}</p>
          <p class="text-muted-foreground text-sm">{@member.user.email}</p>
          <p class="text-muted-foreground mt-2 text-sm">
            Para colocar outra pessoa no lugar, remova esta e adicione a nova — aqui só a função
            muda.
          </p>
        </div>

        <.form_item>
          <.form_label field={@form[:type]}>Função</.form_label>
          <.select
            field={@form[:type]}
            prompt="Escolha a função"
            options={[{"Instrumentista", "instrumentalist"}, {"Vocalista", "vocalist"}]}
          />
          <.form_message field={@form[:type]} />
        </.form_item>

        <.form_item :if={selected_type(@form) == :instrumentalist}>
          <.form_label field={@form[:instrument_id]}>Instrumento</.form_label>
          <.select
            field={@form[:instrument_id]}
            prompt="Escolha o instrumento"
            options={@instrument_options}
          />
          <.form_message field={@form[:instrument_id]} />

          <p id="instrument-catalog-hint" class="text-muted-foreground text-sm">
            A lista é o catálogo do grupo de louvor. Instrumento que a igreja adquiriu e ainda
            não está aqui é cadastrado por Pastor ou Líder de Louvor, em Instrumentos.
          </p>
        </.form_item>

        <.form_item :if={selected_type(@form) == :vocalist}>
          <.form_label field={@form[:voice_part]}>Naipe</.form_label>
          <.select
            field={@form[:voice_part]}
            prompt="Escolha o naipe"
            options={BandMember.voice_parts()}
          />
          <.form_message field={@form[:voice_part]} />
        </.form_item>

        <div class="pt-2">
          <.button phx-disable-with={submitting_label(@live_action)}>
            {submit_label(@live_action)}
          </.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
