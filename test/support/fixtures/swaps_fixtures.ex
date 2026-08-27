defmodule ChurchBands.SwapsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Swaps`.
  """

  alias ChurchBands.Repo
  alias ChurchBands.Swaps.SwapRequest

  @doc """
  Grava um pedido de troca.

  Vai **direto ao repositório**, e não por `Swaps.request_swap/4`: a
  elegibilidade é justamente o que metade dos testes está verificando, e montar
  o cenário por dentro dela obrigaria cada teste a respeitar a regra que ele
  quer ver sendo aplicada. É o mesmo motivo de
  `ScheduleFixtures.event_band_fixture/1` com a janela de conflito.

  As duas escalas e os dois vínculos são obrigatórios: não há pedido sem os
  quatro, e inventar algum esconderia do teste qual é a troca que ele está
  montando. `status` fica de fora do padrão porque pendente é como o pedido
  nasce.
  """
  def swap_request_fixture(attrs) do
    attrs = Map.new(attrs)

    %{
      requester_event_band: requester_event_band,
      requester_member: requester_member,
      target_event_band: target_event_band,
      target_member: target_member
    } = attrs

    %SwapRequest{}
    |> Ecto.Changeset.change(
      requester_event_band_id: requester_event_band.id,
      requester_member_id: requester_member.id,
      target_event_band_id: target_event_band.id,
      target_member_id: target_member.id,
      status: Map.get(attrs, :status, :pending)
    )
    |> Repo.insert!()
  end
end
