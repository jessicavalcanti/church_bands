defmodule ChurchBands.Schedule do
  @moduledoc """
  Contexto do calendário e da escala (Fase 3). Nasce na US 3.1 com os tipos de
  evento — o vocabulário do que a igreja marca na agenda — e ganha na US 3.2 os
  eventos em si.

  Autorização: curar os tipos é exclusivo de Pastor e Líder de Louvor, e a tela
  deles **nunca abre para leitura ampla**. É a diferença para `/songs` e para o
  repertório da banda, que nasceram restritos e abriram depois: o que o resto do
  sistema precisa de um tipo é o **nome** dele, e esse aparece no evento. Por
  isso a permissão mora inteira no hook da rota, e não há predicado próprio
  aqui.

  O evento nasceu na US 3.2 igualmente restrito, e a US 3.3 abriu a leitura:
  `/calendar` e `/events/:id` são de leitura ampla, e é a tela do evento que
  reconfere a permissão de cada escrita.

  **A US 3.4 trouxe a escala, e com ela o primeiro predicado deste contexto.**
  Enquanto a escala não existia, não havia como dizer "de que banda é este
  evento" — e sem isso a permissão cabia inteira no hook. Agora cabe:
  `manage_event?/2` e `create_event_of_type?/2` são a fonte única de quem
  escreve o quê, e a regra que elas escrevem é *quem tem acesso total mexe em
  tudo; o Líder de Banda mexe onde o assunto é dele*.

  **A permissão do líder se lê do estado atual, não da autoria.** Ele edita e
  cancela o evento enquanto o tipo continuar marcado com
  `band_leader_can_create` **e** uma banda que ele lidera continuar escalada.
  É por isso que o evento não guarda quem o criou: desescalar a banda tira o
  evento das mãos dele, e isso é proposital.

  **Tudo aqui fala `DateTime` em UTC.** A hora de parede é assunto da borda
  (`ChurchBands.LocalTime`), e não entra no contexto nem no banco.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.LocalTime
  alias ChurchBands.Realtime
  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Repertoire.Song
  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Schedule.EventBandSong
  alias ChurchBands.Schedule.EventType
  alias ChurchBands.Sorting
  alias Ecto.Multi

  ## Tipos de evento

  @doc """
  Os tipos de evento em ordem alfabética, cada um com quantos eventos o usam
  em `:event_count`.

  A contagem sai do mesmo `left_join` da consulta, e não de uma pergunta por
  linha: é ela que a lista mostra e é ela que escreve a recusa da exclusão —
  o arranjo de `Repertoire.list_tags/0`.

  A ordem sai de `Sorting.by_name/1`, em Elixir, e não de um `ORDER BY`: quem
  ordena no PostgreSQL é a collation, e ela muda com o locale de quem subiu o
  banco — "Confraternização" cairia em lugares diferentes no CI e na máquina de
  quem desenvolve.
  """
  def list_event_types do
    from(t in EventType,
      left_join: e in assoc(t, :events),
      group_by: t.id,
      select: %{t | event_count: count(e.id)}
    )
    |> Repo.all()
    |> Sorting.by_name()
  end

  @doc """
  Busca um tipo de evento pelo id, ou `nil`. Aceita id em string, como
  `Repertoire.get_tag/1`: o que chega pela rota é texto e pode ser qualquer
  texto.
  """
  def get_event_type(id) when is_binary(id), do: RouteId.get(id, &get_event_type/1)

  def get_event_type(id) when is_integer(id), do: Repo.get(EventType, id)

  @doc """
  Cadastra um tipo de evento.
  """
  def create_event_type(attrs) do
    %EventType{}
    |> EventType.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Renomeia um tipo de evento, ou muda a marcação do Líder de Banda.

  A marcação vale a partir de agora e não é retroativa: quem a lê é a criação
  de evento (US 3.4), e o evento já marcado não guarda cópia dela.
  """
  def update_event_type(%EventType{} = event_type, attrs) do
    event_type
    |> EventType.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Exclui um tipo de evento que nenhum evento usa.

  Devolve `{:error, {:in_use, count}}` quando há evento daquele tipo — a
  contagem é consultada antes, e é ela que produz a mensagem. Excluir o tipo
  arrastando os eventos junto apagaria o calendário por um clique numa tela de
  cadastro, e o `on_delete: :nothing` da migration é a rede embaixo disso.

  Não existe `foreign_key_constraint` aqui, pela mesma razão de
  `Repertoire.delete_tag/1`: com a contagem consultada, o erro do banco seria
  um ramo que nenhum teste alcança.
  """
  def delete_event_type(%EventType{} = event_type) do
    case count_type_events(event_type) do
      0 -> Repo.delete(event_type)
      count -> {:error, {:in_use, count}}
    end
  end

  defp count_type_events(%EventType{id: id}) do
    Repo.aggregate(from(e in Event, where: e.event_type_id == ^id), :count)
  end

  @doc """
  Changeset para alimentar o formulário de tipo de evento.
  """
  def change_event_type(%EventType{} = event_type \\ %EventType{}, attrs \\ %{}) do
    EventType.changeset(event_type, attrs)
  end

  ## Eventos

  @doc """
  Os eventos de uma faixa de tempo, em ordem cronológica e com o tipo
  pré-carregado.

  `opts` **exige** `:from` e `:to` (`DateTime` UTC, inclusivos nos dois lados) e
  aceita `:type_id` e `:band_id`. A faixa nasceu opcional na US 3.2, quando a tela era uma
  lista da agenda inteira; a grade da US 3.3 sempre pergunta por um mês, e
  ninguém mais quer a tabela toda. Exigi-la é o que impede que um "listar tudo"
  reapareça sem querer no dia em que a igreja tiver cinco anos de calendário.

  **Quem calcula a faixa é a borda**, com `LocalTime.start_of_day/1` e
  `end_of_day/1`: o mês é um recorte de dias no fuso da igreja, e converter aqui
  faria o contexto voltar a falar hora de parede.

  Aqui a ordem sai do `ORDER BY`, e não de `Sorting`: quem ordena é a data, e
  data não tem collation — o problema que o `Sorting` resolve é de texto.

  **As bandas escaladas vêm juntas** (US 3.4), pelo `has_many through` do
  evento: a grade escreve os nomes delas em cada célula, e perguntá-los evento
  a evento seria uma consulta por dia de mês cheio.
  """
  def list_events(opts) do
    Event
    |> where([e], e.starts_at >= ^Keyword.fetch!(opts, :from))
    |> where([e], e.starts_at <= ^Keyword.fetch!(opts, :to))
    |> filter_type(opts[:type_id])
    |> filter_band(opts[:band_id])
    |> order_by([e], asc: e.starts_at, asc: e.id)
    |> preload([:event_type, :bands])
    |> Repo.all()
  end

  defp filter_type(query, nil), do: query
  defp filter_type(query, type_id), do: where(query, [e], e.event_type_id == ^type_id)

  # O filtro por banda pergunta pela escala, que é outra tabela. Vai por
  # subconsulta, e não por `join`: com o `join`, o evento que tivesse a banda
  # escalada duas vezes sairia duplicado na grade — o índice único impede isso
  # hoje, mas a consulta não deveria depender dele para estar certa.
  defp filter_band(query, nil), do: query

  defp filter_band(query, band_id) do
    scheduled = from(eb in EventBand, where: eb.band_id == ^band_id, select: eb.event_id)

    where(query, [e], e.id in subquery(scheduled))
  end

  @doc """
  Busca um evento pelo id, com o tipo pré-carregado, ou `nil`. Aceita id em
  string, como `get_event_type/1`.
  """
  def get_event(id) when is_binary(id), do: RouteId.get(id, &get_event/1)

  def get_event(id) when is_integer(id) do
    Event
    |> Repo.get(id)
    |> Repo.preload(:event_type)
  end

  @doc """
  Marca um evento na agenda.

  Passa pelo `creation_changeset/2`, que é o que recusa data no passado — a
  única regra que separa criar de editar.
  """
  def create_event(attrs) do
    %Event{}
    |> Event.creation_changeset(attrs)
    |> Repo.insert()
    |> preload_type()
  end

  @doc """
  Corrige um evento, inclusive um que já aconteceu.

  Editar o passado é permitido de propósito: é justamente depois do culto que
  se descobre que o título estava errado.

  **Mudar a data reconfere a janela de conflito** de cada banda escalada
  (US 3.4) e devolve `{:error, {:conflict, banda, evento}}`. A tupla é de três,
  e não de duas como a de `schedule_band/2`: lá a banda em choque é a que se
  está escalando, e quem chamou já a tem na mão; aqui ela sai da escala e
  precisa vir junto para a mensagem poder nomeá-la.
  """
  def update_event(%Event{} = event, attrs) do
    changeset = Event.changeset(event, attrs)

    case rescheduling_conflict(event, changeset) do
      nil -> changeset |> Repo.update() |> preload_type() |> broadcast_event()
      {band, other} -> {:error, {:conflict, band, other}}
    end
  end

  # A janela só se reconfere quando a data mudou **e** o resto do formulário
  # está válido. Perguntar antes disso trocaria a mensagem do campo mal
  # preenchido por uma recusa de conflito que ninguém teria como entender — e
  # `get_change/2` devolver `nil` é o que diz que a data ficou onde estava.
  defp rescheduling_conflict(event, changeset) do
    case {changeset.valid?, Ecto.Changeset.get_change(changeset, :starts_at)} do
      {true, %DateTime{} = starts_at} -> first_conflict(event, starts_at)
      _unchanged_or_invalid -> nil
    end
  end

  @doc """
  Cancela um evento, sem apagar nada.

  O culto cancelado **continua no calendário**, riscado: quem não olhar de novo
  não pode ser surpreendido no domingo. Não há restrição de data — cancelar um
  evento de ontem é registro, e o registro é o ponto.
  """
  def cancel_event(%Event{} = event), do: put_status(event, :cancelled)

  @doc """
  Devolve um evento cancelado a agendado.

  Existe para que cancelar não seja um beco sem saída: sem reabrir, desfazer um
  clique errado viraria recriar o evento do zero.

  Reabrir **reconfere a janela de conflito** (US 3.4), como mudar a data faz.
  Enquanto cancelado o evento não ocupa a banda, então alguma delas pode ter
  sido escalada em outro evento no mesmo horário nesse meio-tempo — reabrir sem
  conferir deixaria o sistema exatamente no estado que a escala proíbe.
  Conflitando, o evento **continua cancelado**.
  """
  def reopen_event(%Event{} = event) do
    case first_conflict(event, event.starts_at) do
      nil -> put_status(event, :scheduled)
      {band, other} -> {:error, {:conflict, band, other}}
    end
  end

  # `status` não passa por changeset de formulário justamente para não poder ser
  # forjado por parâmetro — quem o muda são as duas funções acima.
  defp put_status(%Event{} = event, status) do
    event
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
    |> preload_type()
    |> broadcast_event()
  end

  @doc """
  Exclui um evento que não tem banda escalada.

  Devolve `{:error, {:scheduled, count}}` quando há escala — a contagem é
  consultada antes, e é ela que produz a mensagem. **A saída para o evento que
  não vai mais acontecer é cancelar**, que preserva o registro; excluir
  arrastando a escala junto apagaria da agenda das bandas um compromisso que
  elas já leram.

  Mesma forma da trava de tipo em uso (US 3.1) e da música no repertório
  (US 2.2), e o `on_delete: :nothing` da migration é a rede embaixo dela.
  """
  def delete_event(%Event{} = event) do
    case count_event_bands(event) do
      0 -> event |> Repo.delete() |> broadcast_event()
      count -> {:error, {:scheduled, count}}
    end
  end

  # As três escritas acima e as duas de escala logo abaixo (`schedule_band/2`,
  # `unschedule_band/1`) mudam o que `EventLive.Show` desenha, e por isso
  # publicam no mesmo tópico do evento (#112) — a mensagem é só a campainha,
  # sem dado: quem ouve recarrega por `get_event/1`, a mesma consulta que o
  # mount já usava antes de existir tempo real.
  defp broadcast_event({:ok, event} = result) do
    Realtime.broadcast(Realtime.event_topic(event), :event_updated)
    result
  end

  defp broadcast_event(result), do: result

  # As escritas do set (`add_song_to_set/2`, `update_set_item/2`,
  # `remove_from_set/1`) publicam no tópico da **escala**, não do evento
  # inteiro (#112): é `EventSetLive.Show` quem mais precisa disso, e ela só
  # tem uma banda na tela. `EventLive.Show` também ouve, um tópico por banda
  # escalada, porque mostra o set de todas.
  defp broadcast_event_band({:ok, item} = result) do
    Realtime.broadcast(Realtime.event_band_topic(item), :event_band_updated)
    result
  end

  defp broadcast_event_band(result), do: result

  defp count_event_bands(%Event{id: id}) do
    Repo.aggregate(from(eb in EventBand, where: eb.event_id == ^id), :count)
  end

  @doc """
  Changeset para alimentar o formulário de evento.

  O evento que ainda não existe usa o changeset de criação, porque é ele que
  carrega a recusa de data no passado; o que já existe usa o de edição. É o que
  faz a mesma tela recusar ontem ao criar e aceitar ontem ao corrigir.

  Ao abrir o formulário de um evento gravado, o campo virtual chega preenchido
  com a **hora de parede** — sem isso o `datetime-local` mostraria a hora UTC e
  salvar sem mexer deslocaria o horário.
  """
  def change_event(event \\ %Event{}, attrs \\ %{})

  def change_event(%Event{id: nil} = event, attrs), do: Event.creation_changeset(event, attrs)

  def change_event(%Event{} = event, attrs) do
    event
    |> Map.put(:starts_at_local, local_naive(event.starts_at))
    |> Event.changeset(attrs)
  end

  defp local_naive(starts_at) do
    starts_at
    |> LocalTime.to_local()
    |> DateTime.to_naive()
  end

  # `create_event/1` e `update_event/2` devolvem o evento vindo do banco, sem o
  # tipo carregado — e quem chamou vai escrever o nome dele no flash e na tela.
  defp preload_type({:ok, %Event{} = event}), do: {:ok, Repo.preload(event, :event_type)}
  defp preload_type({:error, _changeset} = error), do: error

  ## Autorização de eventos

  @doc """
  `true` para quem pode editar e cancelar `event`.

  São duas pessoas diferentes: quem tem acesso total, em qualquer evento, e o
  **Líder de Banda**, no evento cujo tipo permite que ele crie **e** em que
  alguma banda que ele lidera está escalada. As duas condições são lidas
  agora, e não de um registro de autoria: desmarcar o tipo em `/event-types`,
  ou desescalar a banda dele, tira o evento das mãos do líder.

  **Excluir não passa por aqui** — continua sendo só de acesso total, porque
  excluir apaga o registro para todo mundo, e não só para a banda de quem
  clicou.
  """
  def manage_event?(%User{} = user, %Event{} = event) do
    Accounts.full_access?(user) or leads_scheduled_band?(user, event)
  end

  defp leads_scheduled_band?(user, event) do
    event = Repo.preload(event, :event_type)

    event.event_type.band_leader_can_create and
      Repo.exists?(
        from(eb in EventBand,
          join: b in Band,
          on: b.id == eb.band_id,
          where: eb.event_id == ^event.id and b.leader_id == ^user.id
        )
      )
  end

  @doc """
  `true` para quem pode marcar um evento **daquele tipo**.

  É aqui que a marcação `band_leader_can_create` da US 3.1 finalmente é lida.
  Quem tem acesso total marca qualquer tipo; o Líder de Banda marca só os
  tipos marcados — e precisa liderar alguma banda, porque o evento que ele cria
  nasce com uma escalada.

  A recusa **não é do changeset**: um changeset não conhece quem está gravando.
  Quem recusa é `create_event_with_band/2`, antes de abrir a transação, e o
  seletor da tela só esconde o que essa recusa já garante.
  """
  def create_event_of_type?(%User{} = user, %EventType{} = event_type) do
    Accounts.full_access?(user) or
      (event_type.band_leader_can_create and Bands.list_led_bands(user) != [])
  end

  @doc """
  `true` para quem pode abrir `/events/new` — quem tem acesso total, ou quem
  lidera alguma banda.

  É a pergunta grossa, do hook da rota: se ela é `false`, não há tipo nenhum
  que a pessoa possa marcar, e abrir o formulário só levaria a uma recusa
  depois de preenchê-lo. A pergunta fina, por tipo, é
  `create_event_of_type?/2`.
  """
  def create_events?(%User{} = user) do
    Accounts.full_access?(user) or Bands.list_led_bands(user) != []
  end

  ## Escala de bandas

  # Como o evento é um ponto no tempo, e não um intervalo — a igreja não sabe
  # dizer a que horas o culto acaba —, a sobreposição real não é calculável. A
  # janela fixa a partir do início é o que a substitui: três horas deixam
  # passar os dois cultos de domingo (9h e 19h) e barram o ensaio marcado em
  # cima do culto.
  @conflict_window_hours 3

  @doc """
  Quantas horas separam dois compromissos da mesma banda.

  Existe como função, e não só como constante, porque a mensagem de recusa e o
  teste da borda precisam do mesmo número que a consulta usa.
  """
  def conflict_window_hours, do: @conflict_window_hours

  @doc """
  O evento agendado que ocupa `band_id` a menos de #{@conflict_window_hours}
  horas de `starts_at`, ou `nil`.

  É a consulta que escalar, criar ensaio e mudar a data compartilham — por isso
  `except_event_id` é obrigatório: quem pergunta sempre está mexendo em algum
  evento, e comparar um evento consigo mesmo daria conflito em toda edição.

  **A borda é aberta**: exatamente #{@conflict_window_hours} horas passa. E
  **evento cancelado não ocupa a banda** — ele não gera conflito nem sofre com
  um, porque não vai acontecer.
  """
  def conflicting_event(band_id, %DateTime{} = starts_at, except_event_id) do
    window = @conflict_window_hours * 60 * 60

    Event
    |> join(:inner, [e], eb in EventBand, on: eb.event_id == e.id)
    |> where([e, eb], eb.band_id == ^band_id)
    |> where([e], e.status == :scheduled and e.id != ^except_event_id)
    |> where([e], e.starts_at > ^DateTime.add(starts_at, -window, :second))
    |> where([e], e.starts_at < ^DateTime.add(starts_at, window, :second))
    |> order_by([e], asc: e.starts_at, asc: e.id)
    |> limit(1)
    |> Repo.one()
  end

  # O primeiro choque das bandas já escaladas em `event`, se `event` passasse a
  # começar em `starts_at`. Serve à mudança de data e à reabertura, que fazem a
  # mesma pergunta por motivos diferentes.
  defp first_conflict(%Event{} = event, %DateTime{} = starts_at) do
    event
    |> list_event_bands()
    |> Enum.find_value(fn event_band ->
      case conflicting_event(event_band.band_id, starts_at, event.id) do
        nil -> nil
        other -> {event_band.band, other}
      end
    end)
  end

  @doc """
  Escala uma banda num evento.

  Devolve `{:error, {:conflict, evento}}` quando a banda já toca a menos de
  #{@conflict_window_hours} horas dali, e `{:error, changeset}` para o resto —
  banda que não existe, banda repetida, banda nenhuma.

  **A validação roda antes da consulta de conflito**, por `apply_action/2`: o
  `band_id` chega do formulário como texto e pode ser qualquer texto, e
  perguntar pela janela com "banana" na mão estouraria um `Ecto.Query.CastError`
  em vez de recusar com uma mensagem.
  """
  def schedule_band(%Event{} = event, band_id) do
    changeset = EventBand.changeset(%EventBand{}, %{"event_id" => event.id, "band_id" => band_id})

    with {:ok, %EventBand{band_id: band_id}} <- Ecto.Changeset.apply_action(changeset, :insert),
         nil <- conflicting_event(band_id, event.starts_at, event.id) do
      changeset |> Repo.insert() |> preload_band() |> broadcast_event()
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      %Event{} = other -> {:error, {:conflict, other}}
    end
  end

  @doc """
  Tira uma banda da escala de um evento.

  Não há trava: desescalar é o conserto de quem escalou errado, e o set daquela
  banda naquele evento (US 3.6) vai junto por ser dela.
  """
  def unschedule_band(%EventBand{} = event_band) do
    # `delete!` e não `delete`: quem chama já tem a linha na mão, e o único
    # jeito de o apagamento falhar seria ela ter sumido entre a tela carregar
    # e o clique — um `{:error, changeset}` aqui seria um ramo que nenhum
    # teste alcança, como em `add_song_to_set/2`.
    event_band = Repo.delete!(event_band)

    Realtime.broadcast(Realtime.event_topic(event_band), :event_updated)

    # `EventSetLive.Show` só assina o tópico da própria escala — é o tópico
    # de quem estava com o set desta banda aberto quando ela foi desescalada,
    # e é ele que dispara o redirect (#112).
    Realtime.broadcast(Realtime.event_band_topic(event_band), :event_band_updated)

    {:ok, event_band}
  end

  @doc """
  A linha de escala daquela banda naquele evento, com a banda pré-carregada, ou
  `nil`.

  Recebe o par, e não o id da linha, porque é o par que o botão da tela conhece
  — e porque perguntar pelos dois é o que faz o id forjado de outra escala não
  casar com nada. O `band_id` vem do navegador e pode ser qualquer texto.
  """
  def get_event_band(event_id, band_id) when is_binary(band_id) do
    RouteId.get(band_id, &get_event_band(event_id, &1))
  end

  def get_event_band(event_id, band_id) when is_integer(band_id) do
    case Repo.get_by(EventBand, event_id: event_id, band_id: band_id) do
      nil -> nil
      event_band -> Repo.preload(event_band, :band)
    end
  end

  @doc """
  As bandas escaladas num evento, em ordem alfabética, cada uma na sua linha de
  escala.

  A ordem sai de `Sorting.key/1` sobre o nome da banda, e não de um `ORDER BY`:
  a ordem alfabética do projeto é sempre em Elixir.
  """
  def list_event_bands(%Event{} = event) do
    EventBand
    |> where([eb], eb.event_id == ^event.id)
    |> preload(:band)
    |> Repo.all()
    |> Enum.sort_by(&Sorting.key(&1.band.name))
  end

  @doc """
  As bandas que ainda **não** estão escaladas naquele evento, em ordem
  alfabética.

  É o que o seletor de escalar oferece: esconder as que já estão é o que evita
  que a recusa de duplicata seja a forma normal de descobrir que a banda já
  tocava ali.
  """
  def list_schedulable_bands(%Event{} = event) do
    scheduled = from(eb in EventBand, where: eb.event_id == ^event.id, select: eb.band_id)

    Band
    |> where([b], b.id not in subquery(scheduled))
    |> Repo.all()
    |> Sorting.by_name()
  end

  @doc """
  Marca um evento **já com uma banda escalada**, numa transação só.

  É o caminho do Líder de Banda: ele não escala ninguém, mas o ensaio que ele
  cria nasce com a banda dele dentro. Ou os dois existem, ou nenhum — um evento
  órfão de escala ficaria sem dono, fora do alcance de quem o criou.

  Recusa antes de abrir a transação o que é permissão: `:unauthorized_type`
  para o tipo que esta pessoa não pode marcar, `:unauthorized_band` para a
  banda que ela não lidera — inclusive banda nenhuma. Dentro da transação
  valem as recusas de sempre: o changeset do evento e a janela de conflito.
  """
  def create_event_with_band(attrs, %User{} = user) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    cond do
      refused_type?(user, attrs["event_type_id"]) -> {:error, :unauthorized_type}
      not led_band?(user, attrs["band_id"]) -> {:error, :unauthorized_band}
      true -> insert_event_with_band(attrs)
    end
  end

  # Tipo ausente, ou que não existe, **não** é recusa de permissão: quem o
  # recusa é o changeset do evento, com a mensagem que aparece no campo. Aqui
  # só se pergunta pelo tipo que existe e que esta pessoa não pode marcar.
  defp refused_type?(user, event_type_id) do
    case get_event_type(to_string(event_type_id)) do
      nil -> false
      event_type -> not create_event_of_type?(user, event_type)
    end
  end

  # Comparado como texto porque o id vem do formulário assim, e `nil` vira `""`
  # — que não é banda nenhuma, e é justamente o que se quer recusar.
  defp led_band?(user, band_id) do
    user
    |> Bands.list_led_bands()
    |> Enum.any?(&(to_string(&1.id) == to_string(band_id)))
  end

  defp insert_event_with_band(attrs) do
    Multi.new()
    |> Multi.insert(:event, Event.creation_changeset(%Event{}, attrs))
    |> Multi.run(:event_band, fn _repo, %{event: event} ->
      case schedule_band(event, attrs["band_id"]) do
        {:ok, event_band} -> {:ok, event_band}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} -> {:ok, Repo.preload(event, :event_type)}
      {:error, :event, changeset, _changes} -> {:error, changeset}
      # `{:conflict, evento}` na esmagadora maioria das vezes: a banda já foi
      # conferida como liderada, e o evento acabou de nascer, então não há
      # duplicata nem banda inexistente a recusar. O motivo passa inteiro para
      # quem chamou em vez de ser destrinchado aqui.
      {:error, :event_band, reason, _changes} -> {:error, reason}
    end
  end

  ## Agenda de cada pessoa

  # O horizonte do bloco "Meus próximos eventos" (US 3.5). O recorte é de
  # tempo, e não dos "próximos N eventos", porque a pergunta que o bloco
  # responde é *o que eu tenho pela frente* — e um mês é o horizonte com que
  # uma escala de igreja é combinada. Vir vazio é uma resposta.
  @upcoming_days 30

  @doc """
  Quantos dias o bloco de próximos eventos enxerga.

  Existe como função, e não só como constante, porque a tela escreve o número
  na mensagem de bloco vazio e o teste da borda precisa do mesmo que a consulta
  usa — o arranjo de `conflict_window_hours/0`.
  """
  def upcoming_days, do: @upcoming_days

  @doc """
  Os eventos dos próximos #{@upcoming_days} dias que dizem respeito a `user`,
  do mais próximo ao mais distante.

  Para quem toca, são os eventos das bandas em que a pessoa é **membro ou
  líder** — liderar conta como participar, inclusive sem vínculo de membro. Para
  **acesso total** é a igreja inteira, inclusive o evento sem banda escalada:
  Pastor e Líder de Louvor podem não estar em banda nenhuma, e a agenda toda é
  assunto deles — o bloco seria sempre vazio para justamente quem mais
  acompanha.

  **O evento cancelado continua na lista**, como na grade (US 3.3): sumir
  esconderia a informação de quem já tinha se programado.

  `opts` aceita `:now`, o instante de referência, `LocalTime.now/0` por padrão.
  Existe para o teste fixar a borda dos #{@upcoming_days} dias sem depender do
  relógio da máquina.

  `opts` aceita também `:include_event_ids` (padrão `[]`), eventos que entram na
  lista **mesmo não sendo de banda nenhuma da pessoa**. Nasce na US 4.4, para o
  dia que alguém assumiu por troca: quem cobre outra banda não é membro dela, e
  sem isso o compromisso que a pessoa aceitou não apareceria na agenda dela.

  O nome não é `:swap_event_ids` de propósito — **esta consulta não precisa
  saber por que** aqueles eventos interessam, e é o que mantém `Schedule` sem
  conhecer `ChurchBands.Swaps`. Quem calcula os ids é quem sabe: a tela compõe
  os dois contextos (ver `ChurchBandsWeb.PageController.home/2`).

  Os ids entram como **parâmetro**, e não como subconsulta nova: continua sendo
  uma consulta só, com ou sem troca.

  **No evento assumido a escala vem inteira**, e não recortada às bandas da
  pessoa como no resto da lista. É o certo: quem vai tocar lá precisa ver em
  que banda vai tocar.

  **É uma consulta só.** O tipo e a escala vêm por `join` com `preload` da
  mesma consulta, e não por `preload` à parte: a tela escreve o tipo e os nomes
  das bandas em cada linha, e perguntá-los depois seria uma consulta por evento.
  É o `join` que também recorta — as bandas da pessoa, ou nada para acesso
  total —, e é dele que sai o critério de quem está em duas bandas escaladas no
  mesmo culto ver **um item só**: o Ecto agrupa as linhas do `join` por evento,
  sem `Enum.group_by/2` depois e sem duplicata.

  **A escala pré-carregada é a que interessa a quem está olhando** — só as
  bandas da pessoa, e todas quando o acesso é total. É recorte de propósito, e
  é a razão de esta função não devolver o evento por `get_event/1`: quem quer a
  escala inteira pergunta a `list_event_bands/1`.
  """
  def list_upcoming_events_for_user(%User{} = user, opts \\ []) do
    now = Keyword.get(opts, :now, LocalTime.now())
    include_event_ids = Keyword.get(opts, :include_event_ids, [])

    Event
    |> where([e], e.starts_at >= ^now)
    |> where([e], e.starts_at <= ^DateTime.add(now, @upcoming_days, :day))
    |> join_schedule(user, include_event_ids)
    |> join(:inner, [e], t in assoc(e, :event_type), as: :type)
    |> join(:left, [schedule: eb], b in assoc(eb, :band), as: :band)
    |> order_by([e], asc: e.starts_at, asc: e.id)
    |> preload([type: t, schedule: eb, band: b], event_type: t, event_bands: {eb, band: b})
    |> Repo.all()
    |> Enum.map(&sort_event_bands/1)
  end

  # Acesso total vê tudo, e o `left_join` é o que deixa passar o evento sem
  # banda nenhuma — a confraternização entra na agenda do Pastor. Para os
  # demais o `join` é interno e a escala é filtrada pelas bandas da pessoa: é o
  # mesmo movimento que responde "este evento é meu?" e "quais das minhas
  # bandas tocam nele?".
  #
  # O `or e.id in ^include_event_ids` é a porta do evento assumido por troca
  # (US 4.4). Lista vazia é `false` no SQL, então quem não tem troca nenhuma
  # continua vendo exatamente o que via.
  #
  # **O `join` de quem toca passou a ser `left`, e o filtro virou `where`.** O
  # natural seria pôr o `or` no `on` do `join` interno — num `where` depois de
  # um `inner`, a linha do evento de outra banda já teria sido descartada e o
  # `or` nunca seria avaliado. Só que **o Ecto não aceita subconsulta no `on`**
  # (`invalid expression for join :on, subqueries aren't supported`), e
  # materializar as bandas da pessoa antes custaria uma consulta a mais.
  #
  # Com `left_join`, a linha do evento de outra banda **chega** ao `where`, e é
  # lá que o `or` a salva. O resultado é o mesmo do `inner` para quem não tem
  # troca: a única diferença entre os dois seria o evento **sem banda
  # nenhuma**, e nele `eb.band_id` é `NULL` — `NULL in (...)` não é verdadeiro,
  # e a confraternização continua fora da agenda de quem só toca.
  #
  # **Acesso total ignora a opção**, e é o certo: ele não tem `where` nenhum, e
  # o evento assumido já estava lá.
  defp join_schedule(query, user, include_event_ids) do
    query = join(query, :left, [e], eb in EventBand, on: eb.event_id == e.id, as: :schedule)

    if Accounts.full_access?(user) do
      query
    else
      where(
        query,
        [e, schedule: eb],
        eb.band_id in subquery(user_band_ids(user)) or e.id in ^include_event_ids
      )
    end
  end

  # As bandas em que a pessoa toca **ou** que ela lidera. É a regra de
  # `Bands.list_user_bands/1` — que inclui o líder sem vínculo de membro —,
  # escrita aqui como subconsulta de ids: aquela devolve o elenco inteiro de
  # cada banda, e carregar banda para depois filtrar evento seria a consulta
  # errada. O que se reaproveita dela é a regra, não a função.
  defp user_band_ids(%User{id: user_id}) do
    from(b in Band,
      left_join: m in BandMember,
      on: m.band_id == b.id and m.user_id == ^user_id,
      where: b.leader_id == ^user_id or not is_nil(m.id),
      select: b.id
    )
  end

  # A ordem alfabética do projeto é sempre em Elixir, por `Sorting.key/1` — e
  # aqui ela incide sobre a escala que já veio junto, sem consulta nova.
  defp sort_event_bands(%Event{} = event) do
    %{event | event_bands: Enum.sort_by(event.event_bands, &Sorting.key(&1.band.name))}
  end

  ## Set do culto

  @doc """
  O set de uma escala: as músicas daquela banda naquele evento, na ordem de
  execução, com a música e **o tom do repertório** já na mão.

  A ordem é por `position`, desempatando por `id` — o desempate é o que a torna
  determinística enquanto duas posições ainda estiverem iguais.

  **É uma consulta só**, e o `left_join` com `band_repertoires` é o ponto dela:
  o item aponta para a música do catálogo, não para a linha do repertório, e a
  banda pode ter largado a música depois — a trava de `future_set_titles/2` só
  segura evento futuro. Quando isso acontece, `band_key` vem `nil`, e é disso
  que a tela tira o <q>fora do repertório da banda</q> em vez de um espaço em
  branco sem explicação.

  `band_key` é virtual: ele não é da linha do set, é do repertório da banda —
  perguntá-lo por item seria uma consulta por música do culto.
  """
  def list_set(%EventBand{} = event_band) do
    from(item in EventBandSong,
      join: song in assoc(item, :song),
      left_join: entry in BandRepertoire,
      on: entry.song_id == item.song_id and entry.band_id == ^event_band.band_id,
      where: item.event_band_id == ^event_band.id,
      order_by: [asc: item.position, asc: item.id],
      preload: [song: song],
      select: %{item | band_key: entry.key}
    )
    |> Repo.all()
  end

  @doc """
  Os sets de **todas** as bandas escaladas num evento, agrupados pela escala:
  `%{event_band_id => [item, ...]}`, cada lista já na ordem de execução.

  É `list_set/1` para o evento inteiro, e existe por causa da tela do evento
  (US 3.7), que mostra o set de cada banda escalada: perguntar banda a banda
  seria uma consulta por linha da escala, e a escala cresce com o número de
  bandas do culto.

  **É uma consulta só**, com o mesmo `left_join` de `list_set/1` — e por isso o
  mesmo `band_key` virtual, e o mesmo `nil` para a música que saiu do
  repertório da banda depois de entrar no set.

  A escala **sem set nenhum não aparece no mapa**, e quem chama pede com
  `Map.get(sets, id, [])`: assim a consulta não precisa saber quais bandas
  estão escaladas, que é pergunta de `list_event_bands/1`.
  """
  def list_sets_for_event(%Event{} = event) do
    from(item in EventBandSong,
      join: event_band in assoc(item, :event_band),
      join: song in assoc(item, :song),
      left_join: entry in BandRepertoire,
      on: entry.song_id == item.song_id and entry.band_id == event_band.band_id,
      where: event_band.event_id == ^event.id,
      order_by: [asc: item.position, asc: item.id],
      preload: [song: song],
      select: %{item | band_key: entry.key}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.event_band_id)
  end

  @doc """
  As músicas que podem entrar no set: o repertório daquela banda **menos as
  arquivadas**, em ordem alfabética de título.

  Em aprendizado entra porque ensaiar no culto o que ainda está sendo aprendido
  é decisão do líder; arquivada fica de fora, que é o que arquivar quis dizer
  na Fase 2. O catálogo geral **não** é oferecido: música nova entra antes no
  repertório, e assim há uma fonte da verdade só.

  **Não esconde o que já está no set**, ao contrário de
  `list_schedulable_bands/1` e de `Repertoire.list_repertoire_candidates/2`:
  repetir é regra aqui — há quem abra e encerre o culto com a mesma canção.

  Devolve as linhas do repertório, e não as músicas: é delas que sai o tom que
  a tela mostra ao lado do título.

  A ordem sai de `Sorting.key/1`, em Elixir, como em todo o projeto.
  """
  def list_set_candidates(%EventBand{} = event_band) do
    from(entry in BandRepertoire,
      join: song in assoc(entry, :song),
      where: entry.band_id == ^event_band.band_id and entry.status != :archived,
      preload: [song: song]
    )
    |> Repo.all()
    |> Enum.sort_by(&{Sorting.key(&1.song.title), &1.song.id})
  end

  @doc """
  Põe uma música no fim do set daquela escala.

  Devolve `{:error, :not_in_repertoire}` para o que não estiver no repertório
  **não arquivado** daquela banda — inclusive a música que não existe e o id
  que não é um id. Os três só se alcançam forçando o formulário, e são a mesma
  recusa para quem lê: *esta não é uma escolha válida*.

  A recusa **não é do changeset**: um changeset olha uma linha só, e "está no
  repertório desta banda" é pergunta de outra tabela. Ela vem antes, como a de
  `create_event_with_band/2`.

  Entra **no fim**, e a posição é a última mais um. Não há reaproveitamento de
  buraco: a ordem é manual, e quem quiser a música em outro lugar a arrasta.
  """
  def add_song_to_set(%EventBand{} = event_band, song_id) do
    case repertoire_song_id(event_band, song_id) do
      nil ->
        {:error, :not_in_repertoire}

      song_id ->
        # `insert!` e não `insert`: passada a conferência do repertório, não
        # sobrou recusa nenhuma para o changeset fazer — a escala vem do
        # socket, a posição é calculada aqui, e a música acabou de ser
        # encontrada no repertório da banda (onde o `on_delete: :restrict` de
        # `band_repertoires` impede que ela suma no meio do caminho). Um
        # `{:error, changeset}` aqui seria um ramo que nenhum teste alcança, e
        # o `!` diz isso em voz alta em vez de fingir que trata.
        item =
          %EventBandSong{}
          |> EventBandSong.changeset(%{
            "event_band_id" => event_band.id,
            "song_id" => song_id,
            "position" => next_position(event_band)
          })
          |> Repo.insert!()

        {:ok, Repo.preload(item, :song)} |> broadcast_event_band()
    end
  end

  # O id chega do formulário como texto e pode ser qualquer texto — o mesmo
  # cuidado de `RouteId`, e por isso a mesma função. O que não for id vira
  # `nil` e cai na recusa, em vez de estourar um `Ecto.Query.CastError`.
  defp repertoire_song_id(%EventBand{} = event_band, song_id) do
    with id when is_integer(id) <- RouteId.get(to_string(song_id), & &1),
         true <- active_repertoire_song?(event_band.band_id, id) do
      id
    else
      _not_a_candidate -> nil
    end
  end

  defp active_repertoire_song?(band_id, song_id) do
    Repo.exists?(
      from(entry in BandRepertoire,
        where:
          entry.band_id == ^band_id and entry.song_id == ^song_id and entry.status != :archived
      )
    )
  end

  defp next_position(%EventBand{id: id}) do
    last =
      Repo.aggregate(
        from(item in EventBandSong, where: item.event_band_id == ^id),
        :max,
        :position
      )

    (last || 0) + 1
  end

  @doc """
  A linha do set daquela escala, com a música pré-carregada, ou `nil`.

  Recebe a escala junto com o id, e não o id sozinho: é o par que faz o id
  forjado do set de outra banda não casar com nada, em vez de mexer num set que
  não é o desta tela. Mesmo arranjo de `get_event_band/2`, e aceita id em
  string pela mesma razão.
  """
  def get_set_item(%EventBand{} = event_band, id) when is_binary(id) do
    RouteId.get(id, &get_set_item(event_band, &1))
  end

  def get_set_item(%EventBand{} = event_band, id) when is_integer(id) do
    case Repo.get_by(EventBandSong, id: id, event_band_id: event_band.id) do
      nil -> nil
      item -> Repo.preload(item, :song)
    end
  end

  @doc """
  Muda o **tom deste evento** de um item do set.

  É o único campo que se edita numa linha do set: música e posição se mudam
  removendo e arrastando. Tom em branco volta a `nil`, que é herdar o tom do
  repertório — o `cast/3` já lê texto vazio como ausência, então não há um
  terceiro valor a tratar. O `Ecto.Enum` recusa sozinho o tom que não é dos 24,
  inclusive o forçado pelo socket.
  """
  def update_set_item(%EventBandSong{} = item, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    item
    |> EventBandSong.changeset(Map.take(attrs, ["key"]))
    |> Repo.update()
    |> broadcast_event_band()
  end

  @doc """
  Tira uma música do set.

  **Não mexe no repertório da banda**: sair do set de um culto não é largar a
  música. Os buracos que a remoção deixa na numeração não são consertados —
  quem lê ordena por `position`, e o valor em si não significa nada.
  """
  def remove_from_set(%EventBandSong{} = item),
    do: item |> Repo.delete() |> broadcast_event_band()

  @doc """
  Regrava as posições do set na ordem de `ids`, de 1 em diante.

  **O conjunto recebido precisa ser exatamente o do set** — os mesmos ids, sem
  faltar nem sobrar nem repetir. Fora disso devolve `{:error, :mismatched_set}`
  e não grava nada: a ordem vem do navegador, e a lista arrastada é a única
  coisa que ele tem para dizer. Aceitar um subconjunto deixaria as demais
  músicas com a posição antiga, embaralhadas com as novas.

  As gravações vão numa `Ecto.Multi`: meio set reordenado é pior do que set
  nenhum reordenado.
  """
  def reorder_set(%EventBand{} = event_band, ids) do
    current =
      Repo.all(
        from(item in EventBandSong, where: item.event_band_id == ^event_band.id, select: item.id)
      )

    requested = ids |> List.wrap() |> Enum.flat_map(&set_item_id/1)

    if Enum.sort(requested) == Enum.sort(current) do
      {:ok, _positions} = Repo.transaction(reposition(requested))
      Realtime.broadcast(Realtime.event_band_topic(event_band), :event_band_updated)
      :ok
    else
      {:error, :mismatched_set}
    end
  end

  # O que não for id é descartado antes da comparação, e não convertido a zero:
  # a lista chega do hook de arraste, e o descarte é o que faz o id inventado
  # quebrar a igualdade dos conjuntos em vez de estourar na consulta. Mesma
  # razão do `to_id/1` de `ChurchBands.Repertoire`.
  defp set_item_id(id) when is_integer(id), do: [id]

  defp set_item_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> [id]
      _not_an_id -> []
    end
  end

  defp set_item_id(_other), do: []

  defp reposition(ids) do
    ids
    |> Enum.with_index(1)
    |> Enum.reduce(Multi.new(), fn {id, position}, multi ->
      Multi.update_all(multi, {:position, id}, from(item in EventBandSong, where: item.id == ^id),
        set: [position: position]
      )
    end)
  end

  @doc """
  Os títulos dos eventos **futuros e não cancelados** daquela banda em que
  `song` está no set, do mais próximo ao mais distante. `[]` quando não há
  nenhum.

  É a trava que a US 2.4 não tinha como ter: enquanto não havia evento no
  sistema, "esta música está marcada para tocar" era um ramo inalcançável.
  Agora `Repertoire.remove_song_from_band/1` pergunta por aqui antes de
  remover.

  **Passado e cancelado não seguram nada**: o set do culto que já aconteceu é
  registro do que foi tocado, e o cancelado não vai acontecer. O set de **outra
  banda** também não — a mesma música é de cada banda por sua conta.

  Sem `?` no nome porque devolve lista, e não booleano: quem chama precisa dos
  títulos para dizer de onde tirar a música, e quantos nomes cabem na frase é
  decisão da tela — como em `Repertoire.delete_song/1`.

  Uma música que entrou duas vezes no mesmo set nomeia o evento **uma vez**: o
  `group_by` é por evento, e não por linha do set.

  `opts` aceita `:now`, o instante de referência, `LocalTime.now/0` por padrão
  — é o que deixa o teste fixar a borda sem depender do relógio da máquina, o
  mesmo arranjo de `list_upcoming_events_for_user/2`.
  """
  def future_set_titles(%Band{} = band, %Song{} = song, opts \\ []) do
    now = Keyword.get(opts, :now, LocalTime.now())

    Repo.all(
      from(item in EventBandSong,
        join: eb in assoc(item, :event_band),
        join: e in assoc(eb, :event),
        where: eb.band_id == ^band.id and item.song_id == ^song.id,
        where: e.starts_at >= ^now and e.status == :scheduled,
        group_by: [e.id, e.title, e.starts_at],
        order_by: [asc: e.starts_at, asc: e.id],
        select: e.title
      )
    )
  end

  @doc """
  `true` para quem pode montar o set daquela escala: acesso total, ou o Líder
  **daquela** banda.

  O líder de *outra* banda escalada no mesmo evento não mexe no set alheio — é
  a diferença para `manage_event?/2`, que aceita o líder de qualquer banda
  escalada porque lá o assunto é o evento inteiro.

  A regra em si é `Bands.band_leader?/2`, reaproveitada e não reescrita: é a
  mesma pergunta que autoriza o repertório daquela banda, e o set é o
  repertório dela num culto.
  """
  def manage_set?(%User{} = user, %EventBand{} = event_band) do
    event_band = Repo.preload(event_band, :band)

    Bands.band_leader?(user, event_band.band)
  end

  defp preload_band({:ok, %EventBand{} = event_band}),
    do: {:ok, Repo.preload(event_band, :band)}

  defp preload_band({:error, _changeset} = error), do: error
end
