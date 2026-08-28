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

  **A US 4.3 acrescentou a resposta**: o alvo escolhe entre *só cobrir* — ele
  assume o dia de quem pediu e mantém o seu — e *trocar o dia*, em que as duas
  vagas mudam de dono; ou recusa. O aceite **vale por si**, sem homologação de
  liderança.

  ## A troca aceita é exceção sobre o elenco, e não escala

  Nada em `band_members` muda quando uma troca é aceita: o elenco do evento
  (US 4.1) continua sendo derivado do vínculo, e a troca é a linha daquele
  elenco **com outro nome em cima** e a marca de que aquilo é provisório —
  `list_accepted_for_event/1` e `apply_to_rosters/2` são esse par. É o que faz
  a troca se desfazer sozinha quando a escala deixa de existir, pelo
  `on_delete: :delete_all` da US 4.2, e é por isso que não há botão de desfazer.

  ## Cada fato avisa por dois canais (US 4.5)

  Os quatro fatos da troca — pedido recebido, pedido cancelado, pedido aceito e
  pedido recusado — entregam **e-mail e notificação** dentro da plataforma, do
  mesmo ponto e depois do commit: `notify_request/1`, `notify_cancelled/1`,
  `notify_accepted/1` e `notify_declined/1`. Elas ficam juntas de propósito —
  separá-las abriria a porta para um fato que avisa por um canal só.

  **A seta continua apontando para um lado:** `ChurchBands.Notifications` não
  sabe o que é uma troca. O que ele recebe é título, texto e caminho já
  escritos, e quem os escreve é quem produziu o fato.

  ## A agenda de cada pessoa também lê a troca (US 4.4)

  `list_accepted_for_user/1`, `assumed_event_ids/2` e `annotate_upcoming/3` são
  o que põe a troca no bloco **Meus próximos eventos**: o dia assumido entra na
  agenda de quem o assumiu, mesmo sem vínculo com a banda, e o dia cedido
  continua lá, marcado. **A seta não se inverte**: quem compõe as duas coisas é
  a tela (`ChurchBandsWeb.PageController.home/2`), e `Schedule` só ganhou uma
  opção de ids a incluir — sem saber por que aqueles eventos interessam.

  ## A janela de conflito, que era da banda, passou a valer por pessoa

  `Schedule.conflicting_event/3` pergunta se uma **banda** já toca a menos de
  `Schedule.conflict_window_hours/0` de um instante. `person_busy_event/3` faz a
  mesma pergunta sobre uma **pessoa** — e usa a mesma constante de propósito:
  duas janelas com números diferentes seriam duas regras, e ninguém saberia
  dizer qual das duas vale num domingo.

  A diferença é o que conta como ocupação. Uma pessoa está num evento quando o
  **vínculo** a põe lá **ou** quando uma **troca aceita** a pôs lá, e não está
  quando **cedeu aquela vaga**. As três coisas são o mesmo dia visto de
  ângulos diferentes, e é por isso que a agenda de uma pessoa não sai de uma
  consulta só.

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
  alias ChurchBands.Notifications
  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Swaps.SwapNotifier
  alias ChurchBands.Swaps.SwapRequest
  alias Ecto.Multi

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
    if open_event?(event) do
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
  aviso não saiu.

  **Desde a US 4.5 a notificação dentro da plataforma sai junto**, e antes do
  e-mail: ela é a que não depende de servidor lá fora, e é ela que faz o alvo
  descobrir que foi chamado mesmo com a caixa de saída fora do ar.
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

      notify_cancelled(cancelled)
    else
      {:error, :ineligible}
    end
  end

  def cancel_request(%User{}, %SwapRequest{}), do: {:error, :ineligible}

  ## Resposta ao pedido (US 4.3)

  @doc """
  `user` pode responder a `request`?

  São três coisas ao mesmo tempo: ele é **o alvo**, o pedido está **pendente**,
  e o **evento de origem** ainda está agendado e no futuro.

  O solicitante não responde ao próprio pedido, e acesso total não responde
  pelos outros — responder é do alvo, e de mais ninguém: a troca é acordo entre
  quem toca.

  **Só a ponta de origem entra aqui.** É ela que diz se ainda há o que
  responder: sem o dia de quem pediu, não há o que cobrir nem o que trocar. O
  **dia do alvo** cancelado ou passado tira só o modo *trocar o dia*, e por
  `swap_mode_available/1` — quem está com o próprio culto cancelado ficou
  **mais** livre para cobrir o outro, e continua podendo recusar em vez de
  deixar o pedido pendente para sempre.
  """
  def respond?(%User{} = user, %SwapRequest{status: :pending} = request) do
    request.target_member.user_id == user.id and
      open_event?(request.requester_event_band.event)
  end

  def respond?(%User{}, %SwapRequest{}), do: false

  @doc """
  **Trocar o dia** é viável neste pedido? `:ok`, ou `{:unavailable, motivo}` com
  `motivo` em `[:target_closed, :already_scheduled, :slot_taken,
  {:conflict, evento}]`.

  A pergunta é sobre o **dia do alvo** e sobre o **solicitante**, que é quem
  passa a tocar nele. As quatro respostas são as quatro coisas que poderiam dar
  errado:

    * `:target_closed` — o dia do alvo foi cancelado ou já passou, e não há dia
      para entregar a ninguém. É a segunda metade da regra 3, que vale só neste
      modo: cobrir e recusar continuam de pé
    * `:already_scheduled` — o solicitante já está escalado no evento do alvo, e
      trocar o poria duas vezes no mesmo palco
    * `:slot_taken` — a vaga do alvo já foi ocupada por outra troca aceita, e
      uma vaga não se troca duas vezes (regra 9.1)
    * `{:conflict, evento}` — o solicitante ficaria com dois compromissos a
      menos de #{Schedule.conflict_window_hours()} horas

  **Recebe só o pedido, e não `(user, request)` como a issue escreveu.** Tudo o
  que ela pergunta está dentro do pedido — quem pediu, o dia do alvo e as duas
  vagas —, e um parâmetro que a função não lê é um parâmetro que mente sobre o
  que ela olha. Quem chama já conferiu `respond?/2`: a tela para desenhar o
  botão, `accept_request/3` antes de abrir a transação.

  **O `:releasing` é o que faz a troca entre dois eventos próximos passar.** O
  solicitante cede a vaga de origem no mesmo ato em que assume a do alvo; sem
  dizer isso à consulta, dois cultos a uma hora um do outro se recusariam por
  um conflito que a própria troca desfaz.
  """
  def swap_mode_available(%SwapRequest{} = request) do
    requester = request.requester_member.user
    target_event = request.target_event_band.event

    cond do
      not open_event?(target_event) ->
        {:unavailable, :target_closed}

      scheduled_at?(requester, target_event) ->
        {:unavailable, :already_scheduled}

      traded_slot?(request.target_event_band_id, request.target_member_id) ->
        {:unavailable, :slot_taken}

      true ->
        conflict_for(requester, target_event,
          releasing: {request.requester_event_band_id, request.requester_member_id}
        )
    end
  end

  @doc """
  O alvo aceita o pedido, em `mode` — `"cover"` ou `"swap"`, como chegam do
  `phx-value` do botão.

  Em **cobrir**, o alvo passa a tocar no evento de origem, no lugar de quem
  pediu, e o dia dele **não muda**: ele toca nos dois. Em **trocar o dia**, além
  disso, quem pediu passa a tocar no dia do alvo.

  **A janela de #{Schedule.conflict_window_hours()} horas é perguntada para os
  dois lados**, e não só para quem responde: em *cobrir*, o alvo ganha um dia e
  não perde nenhum; em *trocar*, cada um ganha o dia do outro e cede o seu — e
  aí as duas perguntas levam `:releasing`. A história escreve a regra 6 só sobre
  *cobrir*, mas a janela existe para ninguém estar em dois palcos ao mesmo
  tempo, e trocar põe o alvo num dia novo do mesmo jeito.

  Devolve `{:error, :ineligible}` para quem não pode responder, para o modo que
  não existe e para o solicitante que virou inelegível; `{:error, :slot_taken}`
  para a vaga que já foi trocada; e `{:error, {:conflict, evento}}` para os dois
  compromissos próximos demais, nomeando o outro evento.

  ## Por que as conferências moram **dentro** da `Ecto.Multi`

  Cada uma delas compara quatro tabelas, e nenhuma é changeset: um changeset vê
  uma linha. Postas antes da transação, elas precisariam ser repetidas dentro —
  o mundo muda entre a tela carregar e o clique —, e a repetição de dentro só
  seria alcançada por uma corrida, que é o tipo de caminho que nunca ganha
  teste e apodrece. Escritas uma vez, no primeiro passo da `Multi`, valem como
  conferência **e** como reconferência: o botão oferecido a quem virou
  inelegível cai aqui, e o `rollback` devolve o pedido pendente inteiro, sem
  metade de troca gravada.

  **Os e-mails ficam fora da transação**, depois do commit, como em
  `request_swap/4`: entregar mensagem dentro de transação é prometer o que o
  `rollback` ainda pode desfazer. E a entrega que falha é dita, não engolida.
  """
  def accept_request(%User{} = user, %SwapRequest{} = request, mode) do
    with {:ok, mode} <- SwapRequest.cast_mode(mode),
         true <- respond?(user, request) do
      Multi.new()
      |> Multi.run(:acceptable, fn _repo, _changes -> acceptable(request, mode) end)
      |> Multi.update(:request, response_changeset(request, :accepted, mode))
      |> Repo.transaction()
      |> case do
        {:ok, %{request: accepted}} -> notify_accepted(accepted)
        {:error, :acceptable, reason, _changes} -> {:error, reason}
      end
    else
      _ -> {:error, :ineligible}
    end
  end

  @doc """
  O alvo recusa o pedido.

  **Não muda escala nenhuma** — é a resposta que só encerra o assunto —, e por
  isso não há transação aqui: é uma linha que muda de estado. Pedido recusado
  não volta a pendente, e a vaga fica livre para um pedido novo.

  Avisar quem pediu é o ponto: ele está esperando resposta, e a recusa em
  silêncio o deixaria contando com alguém que já disse não.
  """
  def decline_request(%User{} = user, %SwapRequest{} = request) do
    if respond?(user, request) do
      {:ok, declined} =
        request
        |> response_changeset(:declined, nil)
        |> Repo.update()

      notify_declined(declined)
    else
      {:error, :ineligible}
    end
  end

  @doc """
  O evento em que `user` já toca a menos de #{Schedule.conflict_window_hours()}
  horas de `starts_at`, ou `nil`.

  É `Schedule.conflicting_event/3` para **pessoa** no lugar de banda, com a
  mesma constante e a mesma borda aberta: exatamente
  #{Schedule.conflict_window_hours()} horas passa. Evento cancelado não ocupa
  ninguém.

  O que muda é o que conta como estar lá, e são duas consultas porque as duas
  origens não se juntam sem `union`:

    1. **o vínculo**, tirando as vagas que uma troca aceita já cedeu — a de
       origem, do lado de quem pediu, e a do alvo quando o modo é *trocar*
    2. **a troca aceita**, que põe a pessoa num evento de que ela não é membro:
       o de origem quando ela é o alvo, e o do alvo quando ela é quem pediu e o
       modo é *trocar*

  ## `opts`

    * `:except_event_id` — **obrigatório**, o evento que está sendo montado
      agora. Sem ele todo aceite acharia conflito consigo mesmo, como em
      `Schedule.conflicting_event/3`
    * `:releasing` — a vaga `{event_band_id, member_id}` que **este** pedido vai
      ceder. Ela ainda não é troca aceita, então a consulta 1 a traz; e é
      justamente aquela de que a pessoa está se livrando. Em *só cobrir* não se
      cede nada, e aí a proximidade é conflito de verdade — o alvo tocaria nos
      dois

  Empate se resolve por `{starts_at, id}`, como em
  `Schedule.conflicting_event/3`: duas telas que nomeiam "o outro evento" com
  eventos diferentes seriam a mesma recusa contada de dois jeitos.
  """
  def person_busy_event(%User{} = user, %DateTime{} = starts_at, opts) do
    except_event_id = Keyword.fetch!(opts, :except_event_id)
    releasing = Keyword.get(opts, :releasing)
    window = window_around(starts_at)

    by_membership =
      user
      |> membership_slots(window, except_event_id)
      |> Enum.reject(&(&1.slot == releasing))
      |> Enum.map(& &1.event)

    by_membership
    |> Enum.concat(assumed_events(user, window, except_event_id))
    |> Enum.sort_by(&{DateTime.to_unix(&1.starts_at), &1.id})
    |> List.first()
  end

  @doc """
  As vagas **daquele evento** que estão trocadas, e quem passou a ocupá-las.

  Cada item é `%{member: %BandMember{}, substitute: %User{}}`: `member` é o
  titular da vaga — o mesmo vínculo que o elenco da US 4.1 já mostra — e
  `substitute` é quem vai tocar no lugar dele.

  Um evento é alcançado por dois lados: pela **origem**, quando alguém dali
  pediu troca e foi atendido, e pelo **destino**, quando o modo foi *trocar o
  dia* e quem pediu assumiu a vaga do alvo. Qual dos dois vale se decide aqui,
  comparando o evento de cada ponta com o que foi perguntado — e é por isso que
  a função devolve a vaga resolvida, e não o pedido cru: o mesmo pedido, lido
  do outro evento, aponta para a outra vaga, e uma banda escalada nos dois dias
  faria a tela marcar a linha errada.

  **Uma consulta**, e é o que o índice parcial de `status = 'accepted'` serve.
  """
  def list_accepted_for_event(%Event{id: event_id}) do
    from(r in SwapRequest,
      join: reb in assoc(r, :requester_event_band),
      join: teb in assoc(r, :target_event_band),
      join: rm in assoc(r, :requester_member),
      join: ru in assoc(rm, :user),
      join: tm in assoc(r, :target_member),
      join: tu in assoc(tm, :user),
      where: r.status == :accepted,
      where: reb.event_id == ^event_id or (teb.event_id == ^event_id and r.mode == :swap),
      select: %{
        origin?: reb.event_id == ^event_id,
        requester_member: rm,
        requester_user: ru,
        target_member: tm,
        target_user: tu
      }
    )
    |> Repo.all()
    |> Enum.map(&swapped_slot/1)
  end

  @doc """
  O elenco da US 4.1 com as vagas trocadas marcadas.

  Cada item passa de `%{user:, member:, leader?:}` para
  `%{user:, member:, leader?:, substitute: nil | %User{}}`: `substitute` é quem
  vai tocar, e `user` continua sendo **o titular da vaga**. A tela escreve
  `entry.substitute || entry.user` e, havendo substituto, acrescenta a marca
  *Provisório* e o <q>no lugar de {entry.user.name}</q>.

  É assim que a ordem da lista continua sendo a da vaga, e não a da pessoa que
  a ocupa hoje: ninguém é reordenado, e quem lê o elenco continua lendo por
  função.

  Recebe o mapa de `Bands.list_rosters/1` inteiro e devolve outro no mesmo
  formato — o líder sem vínculo atravessa com `substitute: nil`, porque vaga
  que não existe não se troca.
  """
  def apply_to_rosters(rosters, accepted) when is_map(rosters) do
    substitutes = Map.new(accepted, &{&1.member.id, &1.substitute})

    Map.new(rosters, fn {band_id, entries} ->
      {band_id, Enum.map(entries, &Map.put(&1, :substitute, substitute_for(&1, substitutes)))}
    end)
  end

  defp substitute_for(%{member: nil}, _substitutes), do: nil
  defp substitute_for(%{member: member}, substitutes), do: Map.get(substitutes, member.id)

  defp swapped_slot(%{origin?: true} = row),
    do: %{member: row.requester_member, substitute: row.target_user}

  defp swapped_slot(%{origin?: false} = row),
    do: %{member: row.target_member, substitute: row.requester_user}

  ## A agenda de cada pessoa enxerga a troca

  @doc """
  As trocas **aceitas** que dizem respeito a `user`, dos dois lados: as que ele
  pediu e as que ele atendeu.

  Devolve os pedidos inteiros, com as duas escalas, os dois eventos e os dois
  vínculos pré-carregados — é o mesmo arranjo de `list_sent/1` e
  `list_received/1`, e por isso a consulta é a mesma. **Uma consulta**, e é
  dela que saem `assumed_event_ids/2` e `annotate_upcoming/3`: as duas
  trabalham em Elixir sobre esta lista, e é assim que o bloco da home continua
  custando duas consultas com ou sem troca.

  Só `:accepted` entra. Pendente ainda não mudou o dia de ninguém, e cancelado
  e recusado nunca mudaram.
  """
  def list_accepted_for_user(%User{} = user) do
    requests()
    |> where([r], r.status == :accepted)
    |> where(
      [requester_member: rm, target_member: tm],
      rm.user_id == ^user.id or tm.user_id == ^user.id
    )
    |> Repo.all()
  end

  @doc """
  Os ids dos eventos que `user` **assumiu** por troca, a partir do que
  `list_accepted_for_user/1` devolveu.

  São o evento de **origem** quando a pessoa é o alvo — nos dois modos, porque
  cobrir e trocar assumem o dia do outro do mesmo jeito — e o evento do **alvo**
  quando ela é quem pediu **e** o modo é `:swap`.

  Recebe a lista, e não o `user` sozinho, porque consultar de novo o que já
  está na mão seria a terceira consulta do bloco — a que o critério de
  desempenho da US 4.4 não admite. O `user` continua vindo junto porque é ele
  que diz de que lado da troca a pessoa está: o mesmo pedido é um dia assumido
  para um e um dia cedido para o outro.

  É a lista que a home passa em `:include_event_ids` para
  `Schedule.list_upcoming_events_for_user/2` — que não precisa saber que veio
  de uma troca.
  """
  def assumed_event_ids(accepted, %User{} = user) when is_list(accepted) do
    for request <- accepted, {event_id, {:assumed, _titular}} <- swap_marks(request, user) do
      event_id
    end
  end

  @doc """
  Os eventos da agenda com a troca escrita em cima, para quem está olhando.

  Cada evento ganha `swap`:

    * `nil` — nada a dizer, é o dia de sempre
    * `{:assumed, titular}` — você vai no lugar de `titular`, e a linha ganha a
      marca *Provisório*
    * `{:released, substituto}` — `substituto` vai no seu lugar

  **O dia cedido não some da lista**, ele é marcado: é o princípio do evento
  cancelado da US 3.3 — quem já tinha se programado precisa *ver* que aquilo
  mudou, e linha que desaparece não avisa ninguém. Some também esconderia que a
  pessoa ainda pode ir, se quiser: ela cedeu a vaga, não foi proibida de
  aparecer.

  Recebe `accepted` já carregado e **não consulta nada** — nem uma vez, nem uma
  por evento. Um evento não é assumido e cedido ao mesmo tempo pela mesma
  pessoa: para ceder é preciso ter vaga lá, e quem tem vaga lá não é alvo de
  pedido para lá (US 4.2).
  """
  def annotate_upcoming(events, %User{} = user, accepted) when is_list(events) do
    marks = Map.new(Enum.flat_map(accepted, &swap_marks(&1, user)))

    Enum.map(events, &%{&1 | swap: Map.get(marks, &1.id)})
  end

  # O que um pedido aceito diz sobre os dias **desta** pessoa. São até duas
  # marcas, e não uma: em *trocar o dia* cada um assume um evento e cede o
  # outro, e as duas linhas aparecem na agenda dos dois.
  #
  # As quatro hipóteses são os dois lados vezes os dois modos, e é o lado que
  # decide o sentido: o mesmo pedido é um dia assumido para quem foi chamado e
  # um dia cedido para quem chamou.
  defp swap_marks(%SwapRequest{} = request, %User{id: user_id}) do
    requester = request.requester_member.user
    target = request.target_member.user
    origin_event_id = request.requester_event_band.event_id
    target_event_id = request.target_event_band.event_id

    cond do
      request.target_member.user_id == user_id and request.mode == :swap ->
        [{origin_event_id, {:assumed, requester}}, {target_event_id, {:released, requester}}]

      request.target_member.user_id == user_id ->
        [{origin_event_id, {:assumed, requester}}]

      request.mode == :swap ->
        [{origin_event_id, {:released, target}}, {target_event_id, {:assumed, target}}]

      true ->
        [{origin_event_id, {:released, target}}]
    end
  end

  # O primeiro passo da `Multi`, e o único que pode recusar. A vaga de origem
  # vale para os dois modos: quem já cedeu aquele dia não o cede de novo.
  defp acceptable(%SwapRequest{} = request, mode) do
    if traded_slot?(request.requester_event_band_id, request.requester_member_id) do
      {:error, :slot_taken}
    else
      acceptable_mode(request, mode)
    end
  end

  defp acceptable_mode(%SwapRequest{} = request, :swap) do
    case swap_mode_available(request) do
      :ok ->
        # Em *trocar*, o alvo também assume o dia de quem pediu — e cede o seu
        # no mesmo ato, que é o que o `:releasing` diz. A regra 6 da história
        # fala só de *cobrir*, mas a janela existe para impedir que alguém
        # esteja em dois palcos ao mesmo tempo, e trocar põe o alvo num dia
        # novo do mesmo jeito: deixar de perguntar aqui seria o buraco que a
        # pergunta do outro modo fecha.
        target_free?(request, releasing: {request.target_event_band_id, request.target_member_id})

      # O dia do alvo fechado e o solicitante já escalado nele não têm mensagem
      # própria: para quem responde, os dois são o mesmo <q>este pedido não pode
      # mais ser respondido</q> — a troca deixou de fazer sentido, e a tela já
      # tinha tirado o botão por esses dois motivos.
      {:unavailable, reason} when reason in [:target_closed, :already_scheduled] ->
        {:error, :ineligible}

      {:unavailable, reason} ->
        {:error, reason}
    end
  end

  # Em *cobrir* o alvo assume o dia de quem pediu e **não cede** o seu: por
  # isso não há `:releasing`, e a proximidade entre os dois é conflito de
  # verdade — ele tocaria nos dois.
  defp acceptable_mode(%SwapRequest{} = request, :cover), do: target_free?(request, [])

  defp target_free?(%SwapRequest{} = request, opts) do
    case conflict_for(request.target_member.user, request.requester_event_band.event, opts) do
      :ok -> {:ok, :available}
      {:unavailable, reason} -> {:error, reason}
    end
  end

  defp conflict_for(%User{} = user, %Event{} = event, opts) do
    opts = Keyword.put(opts, :except_event_id, event.id)

    case person_busy_event(user, event.starts_at, opts) do
      nil -> :ok
      other -> {:unavailable, {:conflict, other}}
    end
  end

  defp response_changeset(%SwapRequest{} = request, status, mode) do
    Ecto.Changeset.change(request,
      status: status,
      mode: mode,
      responded_at: LocalTime.now()
    )
  end

  # A vaga `{event_band_id, member_id}` já mudou de dono por uma troca aceita?
  # As duas pontas contam: a de origem sempre, e a do alvo quando o modo foi
  # *trocar o dia* — em *cobrir* o alvo continua com o dia dele.
  defp traded_slot?(event_band_id, member_id) do
    from(r in SwapRequest,
      where: r.status == :accepted,
      where:
        (r.requester_event_band_id == ^event_band_id and r.requester_member_id == ^member_id) or
          (r.target_event_band_id == ^event_band_id and r.target_member_id == ^member_id and
             r.mode == :swap)
    )
    |> Repo.exists?()
  end

  # `user` já vai estar naquele evento, por vínculo ou por liderança? É a mesma
  # conta de `reject_occupied/2`, para um evento só.
  defp scheduled_at?(%User{} = user, %Event{} = event) do
    [event.id]
    |> occupied_user_ids()
    |> Map.get(event.id, MapSet.new())
    |> MapSet.member?(user.id)
  end

  defp window_around(%DateTime{} = starts_at) do
    seconds = Schedule.conflict_window_hours() * 60 * 60

    {DateTime.add(starts_at, -seconds, :second), DateTime.add(starts_at, seconds, :second)}
  end

  # Os eventos da janela em que o vínculo põe a pessoa, **menos** as vagas que
  # uma troca aceita já cedeu. A vaga vem junto (`{event_band_id, member_id}`)
  # porque é ela, e não o evento, que o `:releasing` identifica: a mesma pessoa
  # pode estar num evento por duas bandas.
  defp membership_slots(%User{id: user_id}, {from_time, to_time}, except_event_id) do
    from(m in BandMember,
      as: :member,
      join: eb in EventBand,
      as: :event_band,
      on: eb.band_id == m.band_id,
      join: e in Event,
      on: e.id == eb.event_id,
      where: m.user_id == ^user_id,
      where: e.status == :scheduled and e.id != ^except_event_id,
      where: e.starts_at > ^from_time and e.starts_at < ^to_time,
      select: %{event: e, slot: {eb.id, m.id}}
    )
    |> without_ceded_slots()
    |> Repo.all()
  end

  # A vaga cedida sai na própria consulta, por anti-join: trazê-la para depois
  # filtrar em Elixir obrigaria a segunda consulta a devolver também as trocas
  # em que a pessoa é quem cede, e a leitura ficaria com duas listas para
  # cruzar em vez de uma para somar.
  #
  # Espera as ligações nomeadas `:event_band` e `:member`, que é o que a vaga é.
  defp without_ceded_slots(query) do
    query
    |> join(:left, [event_band: eb, member: m], r in SwapRequest,
      as: :ceded,
      on:
        r.status == :accepted and
          ((r.requester_event_band_id == eb.id and r.requester_member_id == m.id) or
             (r.target_event_band_id == eb.id and r.target_member_id == m.id and r.mode == :swap))
    )
    |> where([ceded: r], is_nil(r.id))
  end

  # Os eventos da janela que uma troca aceita entregou a esta pessoa: o de
  # origem quando ela é o alvo, e o do alvo quando ela é quem pediu e o modo é
  # *trocar o dia*. As duas hipóteses cabem numa consulta só porque a condição
  # do `join` do evento é a que escolhe entre elas.
  defp assumed_events(%User{id: user_id}, {from_time, to_time}, except_event_id) do
    from(r in SwapRequest,
      join: rm in assoc(r, :requester_member),
      join: tm in assoc(r, :target_member),
      join: reb in assoc(r, :requester_event_band),
      join: teb in assoc(r, :target_event_band),
      join: e in Event,
      on:
        (e.id == reb.event_id and tm.user_id == ^user_id) or
          (e.id == teb.event_id and rm.user_id == ^user_id and r.mode == :swap),
      where: r.status == :accepted,
      where: e.status == :scheduled and e.id != ^except_event_id,
      where: e.starts_at > ^from_time and e.starts_at < ^to_time,
      select: e
    )
    |> Repo.all()
  end

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

  Responder é daqui em diante (US 4.3), e quem decide se cada linha ganha
  botões é `respond?/2` — a mesma pergunta que `accept_request/3` e
  `decline_request/2` refazem no servidor.
  """
  def list_received(%User{} = user) do
    requests()
    |> where([target_member: tm], tm.user_id == ^user.id)
    |> Repo.all()
  end

  @doc """
  Os pedidos **pendentes** de `user` que ainda dá para resolver, separados pelas
  duas pontas: `%{received: [...], sent: [...]}`.

  É o que a home mostra em **Trocas pendentes** (US 4.6), e por isso não é
  `list_sent/1` mais `list_received/1`: aquelas duas são a caixa de entrada
  inteira — todos os estados, todas as datas — e esta é só o que ainda espera
  resposta. Um pedido já respondido, cancelado ou de um dia que passou continua
  em `/swaps`, onde a lista conta a história; na home ele seria uma tarefa que
  não existe mais.

  **O que decide é o evento de origem**, agendado e no futuro: é a mesma
  pergunta de `respond?/2` (US 4.3, regra 3), e é ela que diz se ainda há o que
  cobrir ou trocar. O **dia do alvo** cancelado ou passado **não** tira o pedido
  daqui — ele tira só o modo *trocar o dia* (`swap_mode_available/1`), e quem
  está com o próprio culto cancelado continua podendo cobrir ou recusar. Sumir
  com a linha nesse caso deixaria os dois lados sem ação: um sem responder, o
  outro esperando para sempre.

  **Uma consulta**, com as duas escalas, os dois eventos e os dois vínculos
  pré-carregados: cada linha do bloco escreve quatro nomes, e perguntá-los
  depois seria uma consulta por pedido. A separação das duas pontas é feita em
  Elixir, sobre a lista que já veio — quem é alvo tem o pedido para responder,
  quem é solicitante tem o pedido para esperar.
  """
  def list_pending_for_user(%User{} = user) do
    now = LocalTime.now()

    {received, sent} =
      requests()
      |> where([r], r.status == :pending)
      |> where([requester_event: re], re.status == :scheduled and re.starts_at > ^now)
      |> where(
        [requester_member: rm, target_member: tm],
        rm.user_id == ^user.id or tm.user_id == ^user.id
      )
      |> Repo.all()
      |> Enum.split_with(&(&1.target_member.user_id == user.id))

    %{received: received, sent: sent}
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
  # **A vaga já trocada não sai daqui** (US 4.3, regra 15): quem cedeu o dia
  # não o cede de novo, e uma vaga não se troca duas vezes. O filtro mora nesta
  # consulta, e não em `list_origin_options/2`, porque `requestable_member_ids/2`
  # bebe da mesma fonte — postas em lugares diferentes, as duas discordariam
  # sobre quem ainda pode pedir a quem.
  #
  # A ordem é a do seletor de origem: o compromisso mais próximo primeiro.
  defp origin_slots(%User{id: user_id}) do
    now = LocalTime.now()

    from(m in BandMember,
      as: :member,
      join: eb in EventBand,
      as: :event_band,
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
    |> without_ceded_slots()
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

  # Um evento **aberto**: agendado e ainda por vir. É o que o alvo precisa ter
  # para ser alvo (US 4.2) e o que as duas pontas precisam ter para o pedido
  # ainda poder ser respondido (US 4.3, regra 3) — a mesma pergunta, e por isso
  # a mesma função.
  defp open_event?(%Event{status: :scheduled} = event),
    do: DateTime.after?(event.starts_at, LocalTime.now())

  defp open_event?(%Event{}), do: false

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
      |> notify_request()
    end
  end

  ## Os quatro avisos (US 4.5)

  # Cada fato avisa por **dois canais no mesmo ponto**: a notificação dentro da
  # plataforma e o e-mail. Elas ficam juntas de propósito — separá-las abriria a
  # porta para um fato que avisa por um canal só, que é exatamente o defeito que
  # ninguém percebe. E as duas saem **depois do commit**, fora de qualquer
  # transação: não se anuncia o que um `rollback` ainda pode desfazer.
  #
  # A notificação vem primeiro porque é a que não falha: o e-mail depende de um
  # servidor lá fora, e é ele que devolve `{:error, {:delivery_failed, _}}`.
  # Invertendo a ordem, uma caixa de saída fora do ar deixaria a pessoa sem
  # aviso nenhum — e a central existe justamente para isso não acontecer.
  #
  # **O sentido é o mesmo dos e-mails**: avisa quem **não** agiu. Os dois
  # primeiros vão para o alvo, os dois últimos para quem pediu — quem clicou já
  # sabe o que fez.
  defp notify_request(request) do
    notify(
      request.target_member.user,
      :swap_requested,
      "Pedido de troca de escala",
      "#{requester_name(request)} pediu troca com você em " <>
        "#{slot_line(request.requester_event_band)}. O seu dia em questão é " <>
        "#{slot_line(request.target_event_band)}."
    )

    deliver(request, &SwapNotifier.deliver_request/1)
  end

  defp notify_cancelled(request) do
    notify(
      request.target_member.user,
      :swap_cancelled,
      "Pedido de troca cancelado",
      "#{requester_name(request)} cancelou o pedido de troca com você. O seu dia em " <>
        "#{slot_line(request.target_event_band)} continua como estava."
    )

    deliver(request, &SwapNotifier.deliver_cancelled/1)
  end

  # O aceite é o único que escreve dois textos, e a diferença entre eles é a
  # mesma do e-mail: em *cobrir*, quem pediu só é liberado; em *trocar*, ele é
  # liberado **e** herda o dia do outro. Omitir a segunda metade faria a pessoa
  # faltar num dia que passou a ser dela.
  defp notify_accepted(%SwapRequest{mode: :cover} = request) do
    notify(
      request.requester_member.user,
      :swap_accepted,
      "Pedido de troca aceito",
      "#{target_name(request)} vai cobrir você em " <>
        "#{slot_line(request.requester_event_band)}. O dia dele(a) não muda."
    )

    deliver(request, &SwapNotifier.deliver_accepted/1)
  end

  defp notify_accepted(%SwapRequest{mode: :swap} = request) do
    notify(
      request.requester_member.user,
      :swap_accepted,
      "Pedido de troca aceito",
      "#{target_name(request)} trocou de dia com você: você está liberado de " <>
        "#{slot_line(request.requester_event_band)} e passou a tocar em " <>
        "#{slot_line(request.target_event_band)}."
    )

    deliver(request, &SwapNotifier.deliver_accepted/1)
  end

  defp notify_declined(request) do
    notify(
      request.requester_member.user,
      :swap_declined,
      "Pedido de troca recusado",
      "#{target_name(request)} recusou o seu pedido de troca. O dia continua sendo seu: " <>
        "#{slot_line(request.requester_event_band)}."
    )

    deliver(request, &SwapNotifier.deliver_declined/1)
  end

  # O caminho é o mesmo nos quatro, e por isso mora aqui e não em cada um: a
  # notificação da troca leva sempre à caixa de entrada dela.
  #
  # **É texto, e não `~p`.** O `~p` traria o router para dentro do contexto por
  # um caminho só, e a seta deste módulo já aponta para baixo em tudo o mais.
  # O `?from=notification` é o que faz `/swaps` reconhecer quem chegou por um
  # aviso e poder dizer que o pedido não está mais lá (US 4.5) — quem lê o
  # parâmetro é `ChurchBandsWeb.SwapLive.Index`, e a constante mora aqui para
  # que uma troca de rota se resolva num lugar só.
  @notification_path "/swaps?from=notification"

  # O `{:ok, _}` documenta a invariante em vez de criar um ramo que nenhum
  # caminho alcança — os cinco campos saem daqui prontos, e não há validação que
  # eles possam reprovar. Mesmo papel do `Repo.get_by!` de `target_event_band/2`.
  defp notify(user, kind, title, body) do
    {:ok, _notification} =
      Notifications.notify(user, kind, %{title: title, body: body, path: @notification_path})

    :ok
  end

  # A escala escrita numa linha de notificação: o evento e quando ele é. Sem o
  # nome da banda, que o e-mail carrega — lá o texto é a mensagem inteira, e
  # aqui ele é uma frase que se lê de relance numa lista.
  defp slot_line(event_band) do
    "#{event_band.event.title} — #{LocalTime.format(event_band.event.starts_at, :short)}"
  end

  defp requester_name(request), do: request.requester_member.user.name
  defp target_name(request), do: request.target_member.user.name

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
      as: :requester_event,
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
