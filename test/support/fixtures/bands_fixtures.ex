defmodule ChurchBands.BandsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Bands`.
  """

  import ChurchBands.AccountsFixtures

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Instrument
  alias ChurchBands.Repo

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
  Cria um instrumento no catálogo pelo nome, ou devolve o que já existe.

  A migration da US 2.8 já deixa os onze iniciais cadastrados, e o nome é único
  sem distinguir maiúsculas — pedir "Guitarra" duas vezes tem de devolver a
  mesma, não estourar.
  """
  def instrument_fixture(name) when is_binary(name) do
    case Repo.get_by(Instrument, name: name) do
      nil ->
        {:ok, instrument} = Bands.create_instrument(%{name: name})
        instrument

      instrument ->
        instrument
    end
  end

  @doc """
  Vincula um músico a uma banda. Aceita `:band` e `:user` para reaproveitar
  registros existentes; do contrário cria os dois.

  `:instrument` aceita o **nome** do instrumento e o resolve no catálogo
  (US 2.8), criando o cadastro quando falta — é o que mantém legível o teste que
  só quer dizer "esta pessoa toca cajón". Quem precisa do id passa
  `:instrument_id` direto.
  """
  def band_member_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {band, attrs} = Map.pop_lazy(attrs, :band, &band_fixture/0)
    {user, attrs} = Map.pop_lazy(attrs, :user, &member_fixture/0)

    attrs = attrs |> default_role() |> resolve_instrument()

    {:ok, member} = Bands.add_member(band, user.id, attrs)
    member
  end

  # Sem nada dito, o vínculo é de instrumentista na guitarra. Quem já disse
  # naipe ou instrumento — por nome ou por id — disse o que queria.
  defp default_role(attrs) do
    if Enum.any?([:instrument, :instrument_id, :voice_part], &Map.has_key?(attrs, &1)),
      do: Enum.into(attrs, %{type: :instrumentalist}),
      else: Enum.into(attrs, %{type: :instrumentalist, instrument: "Guitarra"})
  end

  defp resolve_instrument(%{instrument: nil} = attrs), do: Map.delete(attrs, :instrument)

  defp resolve_instrument(%{instrument: name} = attrs) do
    attrs
    |> Map.delete(:instrument)
    |> Map.put(:instrument_id, instrument_fixture(name).id)
  end

  defp resolve_instrument(attrs), do: attrs
end
