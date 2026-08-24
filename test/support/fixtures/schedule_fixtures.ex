defmodule ChurchBands.ScheduleFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Schedule`.
  """

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
end
