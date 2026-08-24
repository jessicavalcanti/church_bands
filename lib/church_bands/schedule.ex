defmodule ChurchBands.Schedule do
  @moduledoc """
  Contexto do calendário e da escala (Fase 3). Nasce na US 3.1 com os tipos de
  evento — o vocabulário do que a igreja marca na agenda.

  Autorização: curar os tipos é exclusivo de Pastor e Líder de Louvor, e a tela
  deles **nunca abre para leitura ampla**. É a diferença para `/songs` e para o
  repertório da banda, que nasceram restritos e abriram depois: o que o resto do
  sistema precisa de um tipo é o **nome** dele, e esse aparece no evento. Por
  isso a permissão mora inteira no hook da rota, e não há predicado próprio
  aqui.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Repo
  alias ChurchBands.RouteId
  alias ChurchBands.Schedule.EventType
  alias ChurchBands.Sorting

  ## Tipos de evento

  @doc """
  Os tipos de evento em ordem alfabética.

  A ordem sai de `Sorting.by_name/1`, em Elixir, e não de um `ORDER BY`: quem
  ordena no PostgreSQL é a collation, e ela muda com o locale de quem subiu o
  banco — "Confraternização" cairia em lugares diferentes no CI e na máquina de
  quem desenvolve.
  """
  def list_event_types do
    EventType
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
  Exclui um tipo de evento.

  Sempre funciona nesta história: não existe evento para segurar o tipo. A
  recusa por tipo em uso nasce na US 3.2, junto da tabela `events`, e é lá que
  ela pode ser escrita com a contagem que produz a mensagem — como em
  `Repertoire.delete_tag/1`.
  """
  def delete_event_type(%EventType{} = event_type) do
    Repo.delete(event_type)
  end

  @doc """
  Changeset para alimentar o formulário de tipo de evento.
  """
  def change_event_type(%EventType{} = event_type \\ %EventType{}, attrs \\ %{}) do
    EventType.changeset(event_type, attrs)
  end
end
