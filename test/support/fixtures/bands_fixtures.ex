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

  @doc """
  Vincula um músico a uma banda. Aceita `:band` e `:user` para reaproveitar
  registros existentes; do contrário cria os dois.
  """
  def band_member_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {band, attrs} = Map.pop_lazy(attrs, :band, &band_fixture/0)
    {user, attrs} = Map.pop_lazy(attrs, :user, &member_fixture/0)

    attrs = Enum.into(attrs, %{type: :instrumentalist, instrument: "Guitarra"})

    {:ok, member} = Bands.add_member(band, user.id, attrs)
    member
  end
end
