defmodule ChurchBands.BandsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Band

  describe "create_band/1" do
    test "cria a banda com nome e líder designado" do
      leader = member_fixture()

      assert {:ok, %Band{} = band} =
               Bands.create_band(%{
                 name: "Banda Jovem",
                 description: "Toca no culto de domingo à noite.",
                 leader_id: leader.id
               })

      assert band.name == "Banda Jovem"
      assert band.description == "Toca no culto de domingo à noite."
      assert band.leader_id == leader.id
      assert band.leader.name == leader.name
    end

    test "exige nome" do
      leader = member_fixture()

      assert {:error, changeset} = Bands.create_band(%{leader_id: leader.id})
      assert %{name: ["informe o nome da banda"]} = errors_on(changeset)
    end

    test "exige um líder designado" do
      assert {:error, changeset} = Bands.create_band(%{name: "Banda Sem Líder"})
      assert %{leader_id: ["escolha o Líder de Banda"]} = errors_on(changeset)
    end

    test "recusa líder que ainda não ativou a conta" do
      pending = user_fixture(%{confirmed_at: nil})

      assert {:error, changeset} =
               Bands.create_band(%{name: "Banda Nova", leader_id: pending.id})

      assert %{leader_id: ["precisa ser alguém com conta ativa no sistema"]} =
               errors_on(changeset)
    end

    test "recusa líder inexistente" do
      assert {:error, changeset} = Bands.create_band(%{name: "Banda Nova", leader_id: 0})

      assert %{leader_id: ["precisa ser alguém com conta ativa no sistema"]} =
               errors_on(changeset)
    end

    test "remove espaços em volta do nome" do
      leader = member_fixture()

      assert {:ok, band} = Bands.create_band(%{name: "  Banda Louvor  ", leader_id: leader.id})
      assert band.name == "Banda Louvor"
    end

    test "recusa nome curto demais" do
      leader = member_fixture()

      assert {:error, changeset} = Bands.create_band(%{name: "A", leader_id: leader.id})
      assert %{name: ["precisa ter entre 2 e 120 caracteres"]} = errors_on(changeset)
    end
  end

  describe "update_band/2" do
    test "atualiza nome e descrição" do
      band = band_fixture(%{name: "Banda Antiga"})

      assert {:ok, band} = Bands.update_band(band, %{name: "Banda Nova", description: "Ajustada"})
      assert band.name == "Banda Nova"
      assert band.description == "Ajustada"
    end

    test "troca o líder e devolve o novo líder pré-carregado" do
      band = band_fixture()
      novo_lider = member_fixture(%{name: "Novo Líder"})

      assert {:ok, band} = Bands.update_band(band, %{leader_id: novo_lider.id})
      assert band.leader_id == novo_lider.id
      assert band.leader.name == "Novo Líder"
    end

    test "recusa nome em branco" do
      band = band_fixture()

      assert {:error, changeset} = Bands.update_band(band, %{name: ""})
      assert %{name: ["informe o nome da banda"]} = errors_on(changeset)
      assert Bands.get_band(band.id).name == band.name
    end
  end

  describe "delete_band/1" do
    test "exclui a banda" do
      band = band_fixture()

      assert {:ok, _band} = Bands.delete_band(band)
      assert Bands.get_band(band.id) == nil
    end
  end

  describe "list_bands/0" do
    test "lista em ordem alfabética com o líder pré-carregado" do
      band_fixture(%{name: "Zion"})
      band_fixture(%{name: "Adoradores"})

      assert ["Adoradores", "Zion"] = Enum.map(Bands.list_bands(), & &1.name)
      assert Enum.all?(Bands.list_bands(), &is_binary(&1.leader.name))
    end
  end

  describe "get_band/1" do
    test "aceita id em string, como vem da rota" do
      band = band_fixture()

      assert Bands.get_band(to_string(band.id)).id == band.id
    end

    test "devolve nil para id inexistente ou inválido" do
      assert Bands.get_band(0) == nil
      assert Bands.get_band("abc") == nil
      assert Bands.get_band("12abc") == nil
    end
  end

  describe "list_leader_candidates/0" do
    test "traz apenas usuários com conta ativa" do
      ativo = member_fixture(%{name: "Ativa"})
      pendente = user_fixture(%{name: "Pendente", confirmed_at: nil})

      nomes = Enum.map(Bands.list_leader_candidates(), & &1.name)

      assert ativo.name in nomes
      refute pendente.name in nomes
    end
  end

  describe "autorização" do
    test "Pastor e Líder de Louvor gerenciam bandas; músico não" do
      assert Bands.manage_bands?(pastor_fixture())
      assert Bands.manage_bands?(worship_leader_fixture())
      refute Bands.manage_bands?(member_fixture())
      refute Bands.manage_bands?(nil)
    end

    test "editar é permitido ao acesso total e ao líder da própria banda" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      outro = member_fixture()

      assert Bands.edit_band?(pastor_fixture(), band)
      assert Bands.edit_band?(worship_leader_fixture(), band)
      assert Bands.edit_band?(leader, band)
      refute Bands.edit_band?(outro, band)
      refute Bands.edit_band?(nil, band)
    end
  end
end
