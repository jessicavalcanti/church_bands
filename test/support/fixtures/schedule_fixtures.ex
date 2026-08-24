defmodule ChurchBands.ScheduleFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Schedule`.
  """

  alias ChurchBands.LocalTime
  alias ChurchBands.Repo
  alias ChurchBands.Schedule

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
