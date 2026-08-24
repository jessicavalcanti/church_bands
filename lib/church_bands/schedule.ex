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

  O evento nasce na US 3.2 igualmente restrito, mas por outra razão: ele abre
  para leitura ampla já na US 3.3, e a escrita pelo Líder de Banda chega na
  US 3.4, quando a escala existir para dizer de que banda o evento é. Enquanto
  isso não existe, quem escreve é só o acesso total, e a permissão continua
  toda no hook.

  **Tudo aqui fala `DateTime` em UTC.** A hora de parede é assunto da borda
  (`ChurchBandsWeb.LocalTime`), e não entra no contexto nem no banco.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventType
  alias ChurchBands.Sorting
  alias ChurchBandsWeb.LocalTime

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
  Os eventos da agenda em ordem cronológica, com o tipo pré-carregado.

  `opts` aceita `:from` e `:to` (`DateTime` UTC, inclusivos) e `:type_id`. A
  faixa nasce **opcional** porque a lista desta história mostra a agenda
  inteira — são dezenas de linhas, e a igreja ainda está montando o primeiro
  mês. A grade da US 3.3 sempre passa uma, porque aí a pergunta é sempre "o que
  acontece neste mês".

  Aqui a ordem sai do `ORDER BY`, e não de `Sorting`: quem ordena é a data, e
  data não tem collation — o problema que o `Sorting` resolve é de texto.
  """
  def list_events(opts \\ []) do
    Event
    |> filter_from(opts[:from])
    |> filter_to(opts[:to])
    |> filter_type(opts[:type_id])
    |> order_by([e], asc: e.starts_at, asc: e.id)
    |> preload(:event_type)
    |> Repo.all()
  end

  defp filter_from(query, nil), do: query
  defp filter_from(query, from), do: where(query, [e], e.starts_at >= ^from)

  defp filter_to(query, nil), do: query
  defp filter_to(query, to), do: where(query, [e], e.starts_at <= ^to)

  defp filter_type(query, nil), do: query
  defp filter_type(query, type_id), do: where(query, [e], e.event_type_id == ^type_id)

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
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
    |> preload_type()
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
  """
  def reopen_event(%Event{} = event), do: put_status(event, :scheduled)

  # `status` não passa por changeset de formulário justamente para não poder ser
  # forjado por parâmetro — quem o muda são as duas funções acima.
  defp put_status(%Event{} = event, status) do
    event
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
    |> preload_type()
  end

  @doc """
  Exclui um evento.

  Sempre funciona nesta história: nada se pendura no evento ainda. A trava do
  evento com banda escalada nasce na US 3.4, junto da tabela que a sustenta.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
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
end
