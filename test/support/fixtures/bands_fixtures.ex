defmodule ChurchBands.BandsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Bands`.
  """

  import ChurchBands.AccountsFixtures

  alias ChurchBands.Bands

  @doc """
  Cria uma banda. Aceita `:leader` para reaproveitar um usuário já existente;
  do contrário cria um músico para liderá-la.
  """
  def band_fixture(attrs \\ %{}) do
    {leader, attrs} = Map.pop_lazy(Map.new(attrs), :leader, &member_fixture/0)

    attrs =
      Enum.into(attrs, %{
        name: "Banda #{System.unique_integer([:positive])}",
        leader_id: leader.id
      })

    {:ok, band} = Bands.create_band(attrs)
    band
  end
end
