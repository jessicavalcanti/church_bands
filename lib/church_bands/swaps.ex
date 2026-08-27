defmodule ChurchBands.Swaps do
  @moduledoc """
  Contexto da troca de escala (Fase 4). Nasce na US 4.2 com o **pedido**: quem
  está escalado e não pode comparecer chama alguém de outra banda que faz a
  mesma função.

  **A troca é exceção sobre a escala, não escala.** Por isso ela não entrou em
  `ChurchBands.Schedule` — e a seta aponta sempre para o mesmo lado: `Swaps`
  conhece `Schedule` e `Bands`; nenhum dos dois conhece `Swaps`. Onde uma tela
  precisar do contrário, quem compõe é quem chama, não o contexto de baixo.

  **O pedido é de vaga para vaga**, e nunca de pessoa para pessoa: a linha
  guarda as duas escalas e os dois vínculos (ver `ChurchBands.Swaps.SwapRequest`).

  **Esta história entrega só o pedido.** O que o alvo ganha aqui é o e-mail e a
  lista; aceitar, recusar e os dois modos — *cobrir* e *trocar o dia* — são da
  US 4.3. É assim de propósito: o pedido precisa existir antes de ter resposta.

  **Pedir troca não depende de papel nenhum.** É acordo entre quem toca, e o
  aceite vale por si, sem aval de liderança. O que decide quem pode pedir a quem
  é a elegibilidade daqui, e não o `global_role`.

  ## Elegibilidade, num lugar só

  Todas as regras de quem pode pedir a quem se resolvem em
  `requestable_member_ids/2` — a lista de alvos possíveis **daquele evento**,
  numa consulta por pergunta e não uma por integrante. `can_request?/3` é a
  mesma pergunta para um alvo, escrita **em cima** dela: as duas não podem
  discordar, e o jeito de garantir isso é uma chamar a outra.

  As regras são:

    * o alvo precisa ter **vínculo** na banda escalada — o Líder de Banda sem
      vínculo (US 1.4) não é alvo, porque sem função não há com o que casar
    * **mesma função, ao pé da letra**: instrumentista só com o mesmo
      instrumento, vocalista só com o mesmo naipe, e os dois nunca entre si
      (`same_role?/2`)
    * o alvo **não é você**
    * o alvo **não pode já estar escalado no evento de origem**, por banda
      nenhuma — é o que impede pedir troca a quem vai estar lá de qualquer
      jeito. É também o que dispensa uma regra de "origem diferente do
      destino": o alvo está escalado no evento dele por definição, então o
      evento dele nunca sobra como origem
    * o **evento do alvo** precisa estar agendado e no futuro
    * o **evento de origem** é um em que você está escalado, pelo vínculo de
      mesma função, agendado e no futuro

  **"Escalado" conta o líder sem vínculo**, como em
  `Schedule.list_upcoming_events_for_user/2`: quem lidera uma banda escalada
  vai estar lá, com ou sem vínculo de membro — e é isso que a regra quer saber.

  ## O que o banco garante, e o que ele não garante

  As quatro chaves e o índice único parcial de um pendente por vaga de origem
  são do banco. A elegibilidade **não é constraint**: mesma função, evento
  futuro e alvo não escalado na origem dependem de comparar linhas de tabelas
  diferentes, e por isso `request_swap/4` reconfere tudo antes de inserir — é
  ela que recusa o formulário forjado.

  Duas dessas conferências são fáceis de esquecer e não têm constraint que as
  pegue: o **vínculo de origem tem de ser da banda da escala de origem e do
  próprio solicitante**, e o **vínculo do alvo tem de ser da banda da escala de
  destino**. Sem elas, um formulário forjado grava um pedido que diz que alguém
  toca numa banda em que não está — e nenhuma foreign key percebe, porque as
  quatro chaves existem de verdade, só não combinam entre si. Aqui as duas
  saem de graça: a origem só pode ser uma das opções que a consulta montou, e a
  escala de destino é procurada **pela banda do vínculo do alvo**.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Swaps.SwapNotifier
  alias ChurchBands.Swaps.SwapRequest

  @doc """
  Os dois vínculos fazem a **mesma função**?

  Instrumentista casa com instrumentista do mesmo instrumento; vocalista, com
  vocalista do mesmo naipe. Instrumentista e vocalista nunca trocam entre si —
  quem falta na banda é a guitarra ou o soprano, não "uma pessoa".

  É a regra escrita num lugar só, e o que a torna barata é ela olhar duas
  linhas já carregadas: `type`, `instrument_id` e `voice_part` são colunas de
  `band_members`, e nenhuma delas precisa do catálogo pré-carregado.
  """
  def same_role?(
        %BandMember{type: :instrumentalist} = a,
        %BandMember{type: :instrumentalist} = b
      ),
      do: a.instrument_id == b.instrument_id

  def same_role?(%BandMember{type: :vocalist} = a, %BandMember{type: :vocalist} = b),
    do: a.voice_part == b.voice_part

  def same_role?(%BandMember{}, %BandMember{}), do: false

  @doc """
  `user` faz, em alguma banda, a mesma função de `target_member`?

  É uma pergunta mais rasa do que `can_request?/3` — não olha evento nenhum —, e
  existe para o hook da rota poder recusar <q>Vocês não fazem a mesma função.</q>
  com a mensagem certa. Sem ela, quem forçasse a URL para um baixo cairia na
  recusa genérica e não saberia o que estava errado.
  """
  def shares_role?(%User{} = user, %BandMember{} = target_member) do
    from(m in BandMember, where: m.user_id == ^user.id)
    |> Repo.all()
    |> Enum.any?(&same_role?(&1, target_member))
  end

  @doc """
  As escalas de `user` que podem ser a **origem** de um pedido a
  `target_member`: os eventos futuros e agendados em que ele está pelo vínculo
  de mesma função do alvo, sem aqueles em que o alvo já está escalado, do mais
  próximo ao mais distante.

  Cada item é `%{event_band: %EventBand{}, member: %BandMember{}, event: %Event{}}`,
  com a banda já pré-carregada na escala — é o que o seletor do formulário
  escreve em cada opção.

  **Lista vazia quer dizer "não pode pedir a esta pessoa"**: sem evento de
  origem não há o que trocar, e é essa a última das regras de elegibilidade.
  """
  def list_origin_options(%User{} = user, %BandMember{} = target_member) do
    slots =
      user
      |> origin_slots()
      |> Enum.filter(&same_role?(&1.member, target_member))

    reject_occupied(slots, target_member.user_id)
  end

  @doc """
  Os ids dos vínculos daquele evento a quem `user` pode pedir troca — um
  `MapSet`, para a tela do evento perguntar por linha do elenco sem consultar
  por linha do elenco.

  `MapSet` e não lista porque a pergunta é de pertinência e o elenco de um culto
  tem dezenas de linhas somando as bandas escaladas.

  Evento cancelado ou que já passou devolve conjunto vazio: é a regra do evento
  do alvo precisar estar agendado e no futuro, e é aqui que ela mora.

  **Nenhuma consulta por integrante.** São três, no máximo: as escalas futuras
  de quem pergunta, quem já está escalado nelas e o elenco do evento aberto. E
  quem não tem escala futura nenhuma custa **uma** — sem origem possível não há
  o que perguntar sobre o elenco.
  """
  def requestable_member_ids(%User{} = user, %Event{} = event) do
    if requestable_event?(event) do
      requestable_from(user, event, origin_slots(user))
    else
      MapSet.new()
    end
  end

  @doc """
  `user` pode pedir troca a `target_member` no evento `event`?

  É `requestable_member_ids/2` para **um** alvo, e está escrita em cima dela de
  propósito: é a mesma regra respondida pelo hook antes do mount e por
  `request_swap/4` antes de gravar, e duas implementações em paralelo acabariam
  discordando no dia em que uma das regras mudasse.

  Recebe o **evento** além do alvo porque o vínculo sozinho não diz em que dia
  a troca foi pedida: a mesma pessoa toca em vários eventos, e as regras do
  alvo — evento agendado, futuro e com a banda dele escalada — são sobre um
  deles.
  """
  def can_request?(%User{} = user, %Event{} = event, %BandMember{} = target_member) do
    user
    |> requestable_member_ids(event)
    |> MapSet.member?(target_member.id)
  end

  @doc """
  Cria o pedido de troca de `user` para `target_member`, saindo da escala
  `origin_event_band_id`.

  Devolve `{:error, :ineligible}` para tudo o que a tela não deveria ter
  oferecido — alvo de função diferente, evento passado, origem em que a pessoa
  não está escalada, origem inventada — e `{:error, changeset}` para o pedido
  pendente repetido, que é o que o índice parcial recusa.

  **Reconfere tudo antes de inserir**, e é essa a razão de ela existir: a tela
  esconde o que não pode, mas esconder o botão nunca foi autorização, e o
  `origin_event_band_id` chega do formulário como texto que pode ser qualquer
  texto — por isso ele passa por `ChurchBands.RouteId`, como em
  `Schedule.get_event_band/2`.

  **O e-mail sai depois da gravação e fora de qualquer transação**, como no
  convite (US 1.1): e-mail entregue dentro de transação promete o que o
  `rollback` ainda pode desfazer.

  **E a entrega que falha é dita, não engolida:** `{:error, {:delivery_failed,
  motivo}}`, como `Accounts.create_invite/2`. O pedido **fica gravado** — ele
  aparece em `/swaps` para os dois lados —, mas quem pediu precisa saber que o
  aviso não saiu: enquanto a notificação dentro da plataforma não existe
  (US 4.5), o e-mail é o único jeito de o alvo descobrir que foi chamado.
  """
  def request_swap(
        %User{} = user,
        %Event{} = event,
        %BandMember{} = target_member,
        origin_event_band_id
      ) do
    case origin_for(user, event, target_member, origin_event_band_id) do
      nil -> {:error, :ineligible}
      origin -> insert_request(origin, event, target_member)
    end
  end

  @doc """
  Cancela um pedido: **só o solicitante, e só enquanto ele está pendente**.

  Devolve `{:error, :ineligible}` para o alvo que tentar cancelar e para o
  pedido que já está cancelado — o segundo é o que faz o clique repetido não
  virar nada. Pedido cancelado **não volta a pendente**: pede-se de novo, e o
  índice parcial deixa.

  **Cancelar avisa o alvo por e-mail.** Ele foi chamado para agir e o pedido
  some da lista dele — sumir em silêncio faria a pessoa procurar o que não está
  mais lá. Como em `request_swap/4`, a entrega que falha vira
  `{:error, {:delivery_failed, motivo}}` — e o pedido **já está cancelado**
  quando isso acontece, porque cancelar é a ação e avisar é a consequência.

  Espera `request` com as associações pré-carregadas, como `get_request/1`
  devolve: é de lá que saem o dono do pedido e o endereço do aviso.
  """
  def cancel_request(%User{} = user, %SwapRequest{status: :pending} = request) do
    if request.requester_member.user_id == user.id do
      {:ok, cancelled} =
        request
        |> Ecto.Changeset.change(status: :cancelled)
        |> Repo.update()

      deliver(cancelled, &SwapNotifier.deliver_cancelled/1)
    else
      {:error, :ineligible}
    end
  end

  def cancel_request(%User{}, %SwapRequest{}), do: {:error, :ineligible}

  @doc """
  Os pedidos que `user` enviou, do mais recente ao mais antigo.
  """
  def list_sent(%User{} = user) do
    requests()
    |> where([requester_member: rm], rm.user_id == ^user.id)
    |> Repo.all()
  end

  @doc """
  Os pedidos que `user` recebeu, do mais recente ao mais antigo.

  Nesta história a lista é **só leitura**: responder é a US 4.3.
  """
  def list_received(%User{} = user) do
    requests()
    |> where([target_member: tm], tm.user_id == ^user.id)
    |> Repo.all()
  end

  @doc """
  Um pedido pelo id, com as duas escalas e os dois vínculos pré-carregados, ou
  `nil`.

  Como `Bands.get_member/1`, aceita id em texto e devolve `nil` para o que não
  for um id.
  """
  def get_request(id) when is_binary(id), do: RouteId.get(id, &get_request/1)

  def get_request(id) when is_integer(id) do
    requests()
    |> where([r], r.id == ^id)
    |> Repo.one()
  end

  ## Elegibilidade

  # As escalas futuras e agendadas em que `user` está **com vínculo** — uma
  # consulta, com o vínculo daquela banda ao lado da escala. É a matéria-prima
  # das duas perguntas de elegibilidade, e é por ela vir inteira de uma vez que
  # nenhuma delas consulta por integrante.
  #
  # A ordem é a do seletor de origem: o compromisso mais próximo primeiro.
  defp origin_slots(%User{id: user_id}) do
    now = LocalTime.now()

    from(m in BandMember,
      join: eb in EventBand,
      on: eb.band_id == m.band_id,
      join: e in Event,
      on: e.id == eb.event_id,
      join: b in Band,
      on: b.id == eb.band_id,
      where: m.user_id == ^user_id,
      where: e.status == :scheduled and e.starts_at > ^now,
      order_by: [asc: e.starts_at, asc: e.id],
      select: %{event_band: eb, member: m, event: e, band: b}
    )
    |> Repo.all()
    |> Enum.map(
      &%{event_band: %{&1.event_band | band: &1.band}, member: &1.member, event: &1.event}
    )
  end

  # O elenco do evento aberto: os vínculos de todas as bandas escaladas nele.
  # O Líder de Banda sem vínculo não aparece aqui, e é justamente a regra —
  # sem função não há com o que casar.
  defp event_members(%Event{id: id}) do
    from(m in BandMember,
      join: eb in EventBand,
      on: eb.band_id == m.band_id,
      where: eb.event_id == ^id
    )
    |> Repo.all()
  end

  # Quem já está escalado em cada um daqueles eventos, por banda nenhuma em
  # particular: os vínculos das bandas escaladas **e** os líderes delas, porque
  # liderar uma banda escalada é estar lá com ou sem vínculo — a mesma conta de
  # `Schedule.list_upcoming_events_for_user/2`.
  defp occupied_user_ids([]), do: %{}

  defp occupied_user_ids(event_ids) do
    from(eb in EventBand,
      join: b in Band,
      on: b.id == eb.band_id,
      left_join: m in BandMember,
      on: m.band_id == eb.band_id,
      where: eb.event_id in ^event_ids,
      select: {eb.event_id, b.leader_id, m.user_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_event_id, leader_id, user_id} -> [leader_id, user_id] end)
    |> Map.new(fn {event_id, ids} -> {event_id, ids |> List.flatten() |> MapSet.new()} end)
  end

  # Tira das escalas de origem aquelas em que `user_id` já vai estar de
  # qualquer jeito.
  defp reject_occupied(slots, user_id) do
    occupied = slots |> Enum.map(& &1.event.id) |> Enum.uniq() |> occupied_user_ids()

    Enum.reject(slots, fn slot ->
      occupied |> Map.get(slot.event.id, MapSet.new()) |> MapSet.member?(user_id)
    end)
  end

  # Sem escala futura nenhuma não há alvo possível, e nem vale perguntar quem
  # está no elenco do evento aberto.
  defp requestable_from(_user, _event, []), do: MapSet.new()

  defp requestable_from(user, event, slots) do
    occupied = slots |> Enum.map(& &1.event.id) |> Enum.uniq() |> occupied_user_ids()

    event
    |> event_members()
    |> Enum.filter(&requestable?(&1, user, slots, occupied))
    |> MapSet.new(& &1.id)
  end

  defp requestable?(%BandMember{} = candidate, %User{} = user, slots, occupied) do
    candidate.user_id != user.id and
      Enum.any?(slots, fn slot ->
        same_role?(slot.member, candidate) and
          not (occupied
               |> Map.get(slot.event.id, MapSet.new())
               |> MapSet.member?(candidate.user_id))
      end)
  end

  defp requestable_event?(%Event{status: :scheduled} = event),
    do: DateTime.after?(event.starts_at, LocalTime.now())

  defp requestable_event?(%Event{}), do: false

  ## Gravação

  # A origem só existe se o pedido inteiro for elegível **e** o id que chegou do
  # formulário for uma das opções que a consulta montou. É essa segunda metade
  # que recusa o evento em que a pessoa não está escalada e o próprio evento do
  # alvo mandados à mão — nenhum dos dois está na lista.
  defp origin_for(user, event, target_member, origin_event_band_id) do
    if can_request?(user, event, target_member) do
      user
      |> list_origin_options(target_member)
      |> find_origin(origin_event_band_id)
    end
  end

  defp find_origin(options, id) when is_binary(id), do: RouteId.get(id, &find_origin(options, &1))

  defp find_origin(options, id) when is_integer(id),
    do: Enum.find(options, &(&1.event_band.id == id))

  defp insert_request(origin, event, target_member) do
    changeset =
      SwapRequest.changeset(%SwapRequest{}, %{
        "requester_event_band_id" => origin.event_band.id,
        "requester_member_id" => origin.member.id,
        "target_event_band_id" => target_event_band(event, target_member).id,
        "target_member_id" => target_member.id
      })

    with {:ok, request} <- Repo.insert(changeset) do
      request.id
      |> get_request()
      |> deliver(&SwapNotifier.deliver_request/1)
    end
  end

  # A entrega é a última coisa que acontece, e o que ela responde chega inteiro
  # a quem chamou: dizer "enviado" quando o servidor de e-mail está fora do ar
  # faria quem pediu esperar por uma resposta que ninguém foi convidado a dar.
  # O registro **fica** — ele existe em `/swaps` para os dois lados —, e é por
  # isso que a recusa nomeia a entrega, e não o pedido. Mesmo formato de
  # `Accounts.create_invite/2`.
  defp deliver(request, notify) do
    case notify.(request) do
      {:ok, _email} -> {:ok, request}
      {:error, reason} -> {:error, {:delivery_failed, reason}}
    end
  end

  # A escala de destino se procura **pela banda do vínculo do alvo**, e é o que
  # torna impossível gravar um pedido em que o vínculo é de uma banda e a escala
  # é de outra. Quem chegou aqui passou por `can_request?/3`, que só diz sim
  # para alvo de banda escalada neste evento — o `get_by!` documenta essa
  # invariante em vez de criar um ramo que nenhum teste alcança.
  defp target_event_band(%Event{} = event, %BandMember{} = target_member) do
    Repo.get_by!(EventBand, event_id: event.id, band_id: target_member.band_id)
  end

  ## Leitura

  # A linha de `/swaps` escreve quatro nomes, duas datas e duas funções, e
  # perguntá-los depois seria uma consulta por pedido. Por isso tudo vem por
  # `join` com `preload` da mesma consulta — o arranjo de
  # `Schedule.list_upcoming_events_for_user/2`.
  #
  # Os dois `left_join` de instrumento são pelo mesmo motivo de
  # `Bands.list_members/1`: com `join` a lista perderia quem canta.
  defp requests do
    from(r in SwapRequest,
      join: reb in assoc(r, :requester_event_band),
      join: re in assoc(reb, :event),
      join: rb in assoc(reb, :band),
      join: rm in assoc(r, :requester_member),
      as: :requester_member,
      join: ru in assoc(rm, :user),
      left_join: ri in assoc(rm, :instrument),
      join: teb in assoc(r, :target_event_band),
      join: te in assoc(teb, :event),
      join: tb in assoc(teb, :band),
      join: tm in assoc(r, :target_member),
      as: :target_member,
      join: tu in assoc(tm, :user),
      left_join: ti in assoc(tm, :instrument),
      order_by: [desc: r.inserted_at, desc: r.id],
      preload: [
        requester_event_band: {reb, event: re, band: rb},
        requester_member: {rm, user: ru, instrument: ri},
        target_event_band: {teb, event: te, band: tb},
        target_member: {tm, user: tu, instrument: ti}
      ]
    )
  end
end
