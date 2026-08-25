defmodule ChurchBands.ScheduleFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Schedule`.
  """

  alias ChurchBands.LocalTime
  alias ChurchBands.Repo
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Schedule.EventBandSong

  @doc """
  Cadastra um tipo de evento.

  O nome padrão é único porque o banco de teste **já nasce com os três tipos
  iniciais** da migration: o teste que precisa de um tipo novo precisa de um
  nome que nenhum deles tenha.

  `band_leader_can_create` fica de fora do padrão de propósito — o teste que
  não fala da marcação não está falando dela, e o `false` do schema responde.
  """
  def event_type_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Enum.into(%{name: "Tipo #{System.unique_integer([:positive])}"})

    {:ok, event_type} = Schedule.create_event_type(attrs)
    event_type
  end

  @doc """
  Marca um evento na agenda.

  O padrão é **futuro**, porque criar no passado é recusado: o teste que quer
  um evento que já aconteceu passa `starts_at` explícito e o fixture o grava
  por cima, depois de criado — é o único jeito, e é o mesmo caminho que a tela
  de edição usa.

  `event_type` aceita um `%EventType{}` pronto; sem ele o fixture cadastra um.
  """
  def event_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {event_type, attrs} = Map.pop_lazy(attrs, :event_type, &event_type_fixture/0)
    {starts_at, attrs} = Map.pop(attrs, :starts_at)
    {status, attrs} = Map.pop(attrs, :status)

    # Criar exige futuro, então o fixture **sempre** cria no futuro: o evento
    # que o teste quer no passado desce depois, em `backdate/2`. Passar a data
    # antiga direto aqui esbarraria na regra que metade dos testes está
    # justamente verificando.
    attrs =
      Enum.into(attrs, %{
        event_type_id: event_type.id,
        title: "Evento #{System.unique_integer([:positive])}",
        starts_at_local: local_naive(future(starts_at))
      })

    {:ok, event} = Schedule.create_event(attrs)

    event
    |> backdate(starts_at)
    |> set_status(status)
  end

  @doc """
  Escala uma banda num evento.

  Vai direto ao repositório, e não por `Schedule.schedule_band/2`: a janela de
  conflito é justamente o que metade dos testes desta escala está verificando,
  e montar o cenário por dentro dela obrigaria cada teste a respeitar a regra
  que ele quer ver sendo aplicada.

  `event` e `band` são obrigatórios — não há escala sem os dois, e inventar um
  deles esconderia do teste qual é o par que ele está montando.
  """
  def event_band_fixture(%{event: event, band: band}) do
    %EventBand{}
    |> Ecto.Changeset.change(event_id: event.id, band_id: band.id)
    |> Repo.insert!()
    |> Repo.preload(:band)
  end

  @doc """
  Põe uma música no set de uma escala (US 3.6).

  Vai direto ao repositório, e não por `Schedule.add_song_to_set/2`: aquela
  exige que a música esteja no repertório não arquivado da banda, e é
  justamente essa recusa que metade dos testes do set está verificando —
  montar o cenário por dentro dela obrigaria cada teste a respeitar a regra que
  ele quer ver sendo aplicada. É o mesmo motivo de `event_band_fixture/1`.

  Passa pelo `changeset/2` do schema, e não por `Ecto.Changeset.change/2` como
  `event_band_fixture/1`: é ele que converte o tom em texto — que é como o
  teste o escreve — no átomo do `Ecto.Enum`. O que ele **não** tem é a regra do
  repertório, que é justamente a de que este fixture precisa escapar.

  `event_band` e `song` são obrigatórios: não há item de set sem os dois.
  `position` entra por padrão como a próxima da fila, para que o teste que não
  fala de ordem não precise contá-la; `key` fica de fora do padrão, porque
  nulo — herdar o tom da banda — é o estado normal de um item.
  """
  def event_band_song_fixture(attrs) do
    attrs = Map.new(attrs)
    %{event_band: event_band, song: song} = attrs

    position =
      Map.get_lazy(attrs, :position, fn ->
        length(Schedule.list_set(event_band)) + 1
      end)

    %EventBandSong{}
    |> EventBandSong.changeset(%{
      "event_band_id" => event_band.id,
      "song_id" => song.id,
      "position" => position,
      "key" => attrs[:key]
    })
    |> Repo.insert!()
    |> Repo.preload(:song)
  end

  @doc """
  Um instante UTC daqui a `days` dias, **no minuto cheio**.

  O segundo vai a zero porque é isso que o `datetime-local` sabe dizer: o campo
  só tem hora e minuto. Fixture com 17:04:32 produziria um evento que a tela de
  edição não consegue reabrir sem perder os 32 segundos — e o teste de "salvar
  sem mexer não desloca o horário" acusaria um deslocamento que só o fixture
  inventou.
  """
  def in_days(days) do
    LocalTime.now()
    |> DateTime.add(days, :day)
    |> Map.put(:second, 0)
  end

  # A data pedida quando ela já é futura; um futuro qualquer quando não é. No
  # segundo caso quem manda é o `backdate/2`, logo depois.
  defp future(nil), do: in_days(7)

  defp future(starts_at) do
    if DateTime.after?(starts_at, LocalTime.now()), do: starts_at, else: in_days(7)
  end

  # O evento que o teste quer no passado se grava direto pelo repositório.
  # Passar pelo `update_event/2` funcionaria — editar o passado é permitido —,
  # mas faria o fixture depender da regra que os testes estão verificando.
  defp backdate(event, nil), do: event

  defp backdate(event, starts_at) do
    event
    |> Ecto.Changeset.change(starts_at: DateTime.truncate(starts_at, :second))
    |> Repo.update!()
  end

  # Só `:cancelled` tem o que fazer: agendado é como o evento já nasce, e um
  # ramo para ele seria ramo que nenhum teste alcança.
  defp set_status(event, nil), do: event

  defp set_status(event, :cancelled) do
    {:ok, event} = Schedule.cancel_event(event)
    event
  end

  defp local_naive(utc) do
    utc
    |> LocalTime.to_local()
    |> DateTime.to_naive()
  end
end
