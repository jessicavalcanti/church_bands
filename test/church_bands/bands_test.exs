defmodule ChurchBands.BandsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember

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

    test "gerenciar integrantes segue a mesma regra da banda" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      outro = member_fixture()

      assert Bands.manage_members?(pastor_fixture(), band)
      assert Bands.manage_members?(worship_leader_fixture(), band)
      assert Bands.manage_members?(leader, band)
      refute Bands.manage_members?(outro, band)
      refute Bands.manage_members?(nil, band)
    end

    test "band_leader?/2 responde pelo líder da banda e pelo acesso total" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      assert Bands.band_leader?(leader, band)
      assert Bands.band_leader?(pastor_fixture(), band)
      refute Bands.band_leader?(member_fixture(), band)
    end
  end

  describe "add_member/3" do
    test "vincula o músico à banda com instrumento" do
      band = band_fixture()
      musician = member_fixture()

      assert {:ok, %BandMember{} = member} =
               Bands.add_member(band, musician.id, %{
                 type: :instrumentalist,
                 instrument: "Guitarra"
               })

      assert member.band_id == band.id
      assert member.user_id == musician.id
      assert member.type == :instrumentalist
      assert member.instrument == "Guitarra"
      assert is_nil(member.voice_part)
      assert member.user.name == musician.name
    end

    test "vincula o músico à banda com naipe" do
      band = band_fixture()
      musician = member_fixture()

      assert {:ok, member} =
               Bands.add_member(band, musician.id, %{type: :vocalist, voice_part: "Contralto"})

      assert member.type == :vocalist
      assert member.voice_part == "Contralto"
      assert is_nil(member.instrument)
    end

    test "o mesmo músico pertence a várias bandas, com função própria em cada uma" do
      musician = member_fixture()
      banda_x = band_fixture()
      banda_y = band_fixture()

      assert {:ok, na_x} =
               Bands.add_member(banda_x, musician.id, %{
                 type: :instrumentalist,
                 instrument: "Guitarra"
               })

      assert {:ok, na_y} =
               Bands.add_member(banda_y, musician.id, %{type: :vocalist, voice_part: "Tenor"})

      assert na_x.instrument == "Guitarra"
      assert na_y.voice_part == "Tenor"
      assert [^musician | []] = Enum.map(Bands.list_members(banda_x), & &1.user)
      assert [^musician | []] = Enum.map(Bands.list_members(banda_y), & &1.user)
    end

    test "recusa o mesmo músico duas vezes na mesma banda" do
      band = band_fixture()
      musician = member_fixture()
      band_member_fixture(%{band: band, user: musician})

      assert {:error, changeset} =
               Bands.add_member(band, musician.id, %{type: :vocalist, voice_part: "Baixo"})

      assert %{user_id: ["este músico já é integrante desta banda"]} = errors_on(changeset)
    end

    test "recusa músico que ainda não ativou a conta" do
      band = band_fixture()
      pending = user_fixture(%{confirmed_at: nil})

      assert {:error, changeset} =
               Bands.add_member(band, pending.id, %{
                 type: :instrumentalist,
                 instrument: "Baixo"
               })

      assert %{user_id: ["precisa ser alguém com conta ativa no sistema"]} = errors_on(changeset)
    end

    test "exige que um músico seja escolhido" do
      band = band_fixture()

      assert {:error, changeset} =
               Bands.add_member(band, nil, %{type: :instrumentalist, instrument: "Baixo"})

      assert %{user_id: ["escolha o músico"]} = errors_on(changeset)
    end

    test "exige a função" do
      band = band_fixture()

      assert {:error, changeset} = Bands.add_member(band, member_fixture().id, %{})
      assert %{type: ["escolha a função"]} = errors_on(changeset)
    end

    test "instrumentista exige instrumento e vocalista exige naipe" do
      band = band_fixture()

      assert {:error, changeset} =
               Bands.add_member(band, member_fixture().id, %{type: :instrumentalist})

      assert %{instrument: ["informe o instrumento"]} = errors_on(changeset)

      assert {:error, changeset} =
               Bands.add_member(band, member_fixture().id, %{type: :vocalist})

      assert %{voice_part: ["escolha o naipe"]} = errors_on(changeset)
    end

    test "recusa naipe fora da lista" do
      band = band_fixture()

      assert {:error, changeset} =
               Bands.add_member(band, member_fixture().id, %{
                 type: :vocalist,
                 voice_part: "Barítono"
               })

      assert %{voice_part: ["escolha um naipe válido"]} = errors_on(changeset)
    end

    test "descarta o campo que não pertence à função escolhida" do
      band = band_fixture()

      assert {:ok, member} =
               Bands.add_member(band, member_fixture().id, %{
                 type: :vocalist,
                 voice_part: "Soprano",
                 instrument: "Guitarra"
               })

      assert is_nil(member.instrument)
    end

    test "remove espaços em volta do instrumento" do
      band = band_fixture()

      assert {:ok, member} =
               Bands.add_member(band, member_fixture().id, %{
                 type: :instrumentalist,
                 instrument: "  Teclado  "
               })

      assert member.instrument == "Teclado"
    end
  end

  describe "list_members/1" do
    test "lista os integrantes da banda com o músico pré-carregado" do
      band = band_fixture()
      outra_banda = band_fixture()
      ana = member_fixture(%{name: "Ana"})
      bruno = member_fixture(%{name: "Bruno"})

      band_member_fixture(%{band: band, user: bruno, type: :vocalist, voice_part: "Tenor"})
      band_member_fixture(%{band: band, user: ana})
      band_member_fixture(%{band: outra_banda})

      assert [ana_membro, bruno_membro] = Bands.list_members(band)
      assert ana_membro.user.name == "Ana"
      assert bruno_membro.user.name == "Bruno"
    end

    test "banda sem integrantes devolve lista vazia" do
      assert Bands.list_members(band_fixture()) == []
    end
  end

  describe "remove_member/1" do
    test "desfaz o vínculo sem apagar o usuário" do
      member = band_member_fixture()

      assert {:ok, _member} = Bands.remove_member(member)
      assert Bands.list_members(member.band_id) == []
      assert ChurchBands.Accounts.get_user(member.user_id)
    end

    test "excluir a banda leva junto os vínculos" do
      member = band_member_fixture()

      assert {:ok, _band} = Bands.delete_band(member.band)
      refute Bands.get_member(member.id)
    end
  end

  describe "list_roster/1" do
    test "o líder abre o elenco mesmo sem função definida" do
      leader = member_fixture(%{name: "Carla"})
      band = band_fixture(%{leader: leader})
      band_member_fixture(%{band: band, user: member_fixture(%{name: "Ana"})})

      assert [primeiro, segundo] = Bands.list_roster(band)

      assert primeiro.user.id == leader.id
      assert primeiro.leader?
      assert is_nil(primeiro.member)

      assert segundo.user.name == "Ana"
      refute segundo.leader?
      assert segundo.member
    end

    test "o líder com vínculo aparece uma vez só, no topo, com a função dele" do
      leader = member_fixture(%{name: "Zuleica"})
      band = band_fixture(%{leader: leader})
      band_member_fixture(%{band: band, user: member_fixture(%{name: "Ana"})})
      band_member_fixture(%{band: band, user: leader, type: :vocalist, voice_part: "Soprano"})

      assert [primeiro, segundo] = Bands.list_roster(band)

      assert primeiro.user.id == leader.id
      assert primeiro.leader?
      assert primeiro.member.voice_part == "Soprano"
      assert segundo.user.name == "Ana"
    end

    test "banda sem vínculo nenhum ainda tem o líder no elenco" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      assert [%{leader?: true, member: nil, user: %{id: id}}] = Bands.list_roster(band)
      assert id == leader.id
    end
  end

  describe "list_member_candidates/2" do
    setup do
      leader = member_fixture(%{name: "Carla Líder"})

      %{
        band: band_fixture(%{leader: leader}),
        leader: leader,
        ana: member_fixture(%{name: "Ana Souza", email: "ana@exemplo.com"})
      }
    end

    test "sem busca, traz todas as contas ativas disponíveis", %{
      band: band,
      leader: leader,
      ana: ana
    } do
      ids = Enum.map(Bands.list_member_candidates(band), & &1.id)

      assert ana.id in ids
      assert leader.id in ids
    end

    test "a busca estreita por nome e por e-mail", %{band: band, ana: ana} do
      assert [%{id: id}] = Bands.list_member_candidates(band, "ana sou")
      assert id == ana.id

      assert [%{id: ^id}] = Bands.list_member_candidates(band, "ANA@EXEMPLO")
    end

    test "não traz quem já é integrante da banda", %{band: band, ana: ana} do
      band_member_fixture(%{band: band, user: ana})

      refute ana.id in Enum.map(Bands.list_member_candidates(band), & &1.id)
      assert Bands.list_member_candidates(band, "ana") == []
    end

    test "o líder some da lista depois de ganhar função", %{band: band, leader: leader} do
      band_member_fixture(%{band: band, user: leader})

      refute leader.id in Enum.map(Bands.list_member_candidates(band), & &1.id)
    end

    test "não traz quem ainda não ativou a conta", %{band: band} do
      pendente = user_fixture(%{name: "Pendente Silva", confirmed_at: nil})

      refute pendente.id in Enum.map(Bands.list_member_candidates(band), & &1.id)
      assert Bands.list_member_candidates(band, "pendente") == []
    end

    test "quem toca em outra banda continua disponível", %{band: band, ana: ana} do
      band_member_fixture(%{band: band, user: ana})

      assert [%{id: id}] = Bands.list_member_candidates(band_fixture(), "ana")
      assert id == ana.id
    end

    test "busca em branco é o mesmo que não filtrar", %{band: band} do
      todos = Bands.list_member_candidates(band)

      assert Bands.list_member_candidates(band, "") == todos
      assert Bands.list_member_candidates(band, "   ") == todos
    end
  end
end
