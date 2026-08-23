defmodule ChurchBands.AccountsFixturesTest do
  @moduledoc """
  O contrato das fixtures (DT-3): todas aceitam mapa **ou** lista de palavras-
  chave.

  `user_fixture/1` e `invite_fixture/1` sempre aceitaram as duas formas; as três
  derivadas estouravam com `BadMapError` na lista, então a mesma chamada
  funcionava ou não dependendo da fixture escolhida. Este teste é o que impede
  a assimetria de voltar.
  """
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures

  test "as fixtures de usuário aceitam lista de palavras-chave" do
    assert pastor_fixture(name: "Ana Pastora").global_role == :pastor
    assert worship_leader_fixture(name: "Bruno Louvor").global_role == :worship_leader
    assert member_fixture(name: "Carla Musicista").name == "Carla Musicista"
    assert user_fixture(global_role: :pastor).global_role == :pastor
  end

  test "as fixtures de usuário aceitam mapa" do
    assert pastor_fixture(%{name: "Ana Pastora"}).global_role == :pastor
    assert worship_leader_fixture(%{name: "Bruno Louvor"}).global_role == :worship_leader
    assert member_fixture(%{name: "Carla Musicista"}).name == "Carla Musicista"
  end

  test "o papel pedido pela fixture vence o que vier nos atributos" do
    # `pastor_fixture/1` existe para dar um pastor; deixar `global_role` passar
    # por cima faria o nome da fixture mentir.
    assert pastor_fixture(global_role: :member).global_role == :pastor
  end

  test "as fixtures de banda aceitam as duas formas" do
    leader = member_fixture()

    assert band_fixture(leader: leader).leader_id == leader.id
    assert band_fixture(%{leader: leader}).leader_id == leader.id
    assert band_member_fixture(instrument: "Cavaquinho").instrument.name == "Cavaquinho"
    assert invite_fixture(email: "convidado@exemplo.com").email == "convidado@exemplo.com"
  end
end
