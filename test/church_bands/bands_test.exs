defmodule ChurchBands.BandsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures

  alias ChurchBands.Bands
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Bands.Instrument

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

  describe "nome único de banda (DT-4)" do
    test "não cadastra duas bandas com o mesmo nome" do
      leader = member_fixture()
      assert {:ok, _} = Bands.create_band(%{name: "Banda Jovem", leader_id: leader.id})

      assert {:error, changeset} =
               Bands.create_band(%{name: "Banda Jovem", leader_id: leader.id})

      assert "já existe uma banda com esse nome" in errors_on(changeset).name
    end

    test "maiúsculas não fazem um nome novo" do
      leader = member_fixture()
      assert {:ok, _} = Bands.create_band(%{name: "Banda Jovem", leader_id: leader.id})

      # Para quem lê uma lista de escolha, é a mesma banda.
      assert {:error, changeset} =
               Bands.create_band(%{name: "banda JOVEM", leader_id: leader.id})

      assert "já existe uma banda com esse nome" in errors_on(changeset).name
    end

    test "renomear para um nome já usado é recusado" do
      leader = member_fixture()
      {:ok, _} = Bands.create_band(%{name: "Banda Jovem", leader_id: leader.id})
      {:ok, outra} = Bands.create_band(%{name: "Banda Domingo", leader_id: leader.id})

      assert {:error, changeset} = Bands.update_band(outra, %{name: "Banda Jovem"})
      assert "já existe uma banda com esse nome" in errors_on(changeset).name
    end

    test "salvar a banda sem mexer no nome continua valendo" do
      leader = member_fixture()
      {:ok, band} = Bands.create_band(%{name: "Banda Jovem", leader_id: leader.id})

      assert {:ok, band} = Bands.update_band(band, %{description: "Culto de domingo."})
      assert band.name == "Banda Jovem"
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

    test "conta o líder sem vínculo, e não conta duas vezes quem lidera e toca" do
      sem_vinculos = band_fixture(%{name: "Adoradores"})

      lider = member_fixture()
      com_musicos = band_fixture(%{name: "Zion", leader: lider})
      band_member_fixture(%{band: com_musicos, user: member_fixture()})
      band_member_fixture(%{band: com_musicos, user: lider})

      counts = Map.new(Bands.list_bands(), &{&1.id, &1.roster_count})

      # O líder sozinho já é elenco...
      assert counts[sem_vinculos.id] == 1
      # ...e não é contado duas vezes quando também tem vínculo.
      assert counts[com_musicos.id] == 2
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
                 instrument_id: instrument_fixture("Guitarra").id
               })

      assert member.band_id == band.id
      assert member.user_id == musician.id
      assert member.type == :instrumentalist
      assert member.instrument.name == "Guitarra"
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
                 instrument_id: instrument_fixture("Guitarra").id
               })

      assert {:ok, na_y} =
               Bands.add_member(banda_y, musician.id, %{type: :vocalist, voice_part: "Tenor"})

      assert na_x.instrument.name == "Guitarra"
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
                 instrument_id: instrument_fixture("Baixo").id
               })

      assert %{user_id: ["precisa ser alguém com conta ativa no sistema"]} = errors_on(changeset)
    end

    test "exige que um músico seja escolhido" do
      band = band_fixture()

      assert {:error, changeset} =
               Bands.add_member(band, nil, %{
                 type: :instrumentalist,
                 instrument_id: instrument_fixture("Baixo").id
               })

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

      assert %{instrument_id: ["informe o instrumento"]} = errors_on(changeset)

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
                 instrument_id: instrument_fixture("Guitarra").id
               })

      assert is_nil(member.instrument_id)
      assert is_nil(member.instrument)
    end

    test "recusa instrumento que não está no catálogo" do
      band = band_fixture()

      assert {:error, changeset} =
               Bands.add_member(band, member_fixture().id, %{
                 type: :instrumentalist,
                 instrument_id: 0
               })

      assert %{instrument_id: ["escolha um instrumento da lista"]} = errors_on(changeset)
    end
  end

  describe "BandMember" do
    test "as duas funções possíveis dentro de uma banda" do
      assert BandMember.types() == [:instrumentalist, :vocalist]
    end

    test "os naipes aceitos para vocalistas" do
      assert "Soprano" in BandMember.voice_parts()
      assert "Tenor" in BandMember.voice_parts()
    end

    test "a função escrita como ela aparece na tela" do
      bateria = %Instrument{name: "Bateria"}

      assert BandMember.role_label(%BandMember{type: :instrumentalist, instrument: bateria}) ==
               "Bateria"

      assert BandMember.role_label(%BandMember{type: :vocalist, voice_part: "Tenor"}) ==
               "Vocal — Tenor"
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

  describe "get_member/1" do
    test "traz o vínculo com músico e banda pré-carregados" do
      member = band_member_fixture()

      encontrado = Bands.get_member(member.id)

      assert encontrado.id == member.id
      assert encontrado.user.id == member.user_id
      assert encontrado.band.id == member.band_id
    end

    test "aceita id em string, como vem da rota" do
      member = band_member_fixture()

      assert Bands.get_member(to_string(member.id)).id == member.id
    end

    test "devolve nil para id inexistente ou inválido" do
      assert Bands.get_member(0) == nil
      assert Bands.get_member("abc") == nil
      assert Bands.get_member("12abc") == nil
    end
  end

  describe "update_member/2" do
    test "corrige o instrumento mantendo o mesmo vínculo" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Bateria"})
      cajon = instrument_fixture("Cajón")

      assert {:ok, corrigido} = Bands.update_member(member, %{instrument_id: cajon.id})
      assert corrigido.id == member.id
      assert corrigido.instrument.name == "Cajón"
      assert corrigido.type == :instrumentalist
    end

    test "trocar de instrumentista para vocalista zera o instrumento" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Guitarra"})

      assert {:ok, corrigido} =
               Bands.update_member(member, %{type: :vocalist, voice_part: "Tenor"})

      assert corrigido.type == :vocalist
      assert corrigido.voice_part == "Tenor"
      assert is_nil(corrigido.instrument)
    end

    test "trocar de vocalista para instrumentista zera o naipe" do
      member = band_member_fixture(%{type: :vocalist, voice_part: "Soprano", instrument: nil})

      assert {:ok, corrigido} =
               Bands.update_member(member, %{
                 type: :instrumentalist,
                 instrument_id: instrument_fixture("Violino").id
               })

      assert corrigido.type == :instrumentalist
      assert corrigido.instrument.name == "Violino"
      assert is_nil(corrigido.voice_part)
    end

    test "vocalista sem naipe é recusado" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Baixo"})

      assert {:error, changeset} = Bands.update_member(member, %{type: :vocalist})
      assert "escolha o naipe" in errors_on(changeset).voice_part
    end

    test "não troca o músico nem a banda, mesmo se forjados" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Teclado"})
      outro_musico = member_fixture()
      outra_banda = band_fixture()

      assert {:ok, corrigido} =
               Bands.update_member(member, %{
                 "user_id" => outro_musico.id,
                 "band_id" => outra_banda.id,
                 "instrument_id" => instrument_fixture("Piano").id
               })

      assert corrigido.user_id == member.user_id
      assert corrigido.band_id == member.band_id
      assert corrigido.instrument.name == "Piano"
      assert Bands.list_members(outra_banda) == []
    end

    test "instrumento em branco apaga o que estava gravado" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Guitarra"})

      assert {:ok, corrigido} =
               Bands.update_member(member, %{
                 "type" => "vocalist",
                 "voice_part" => "Tenor",
                 "instrument_id" => ""
               })

      assert is_nil(corrigido.instrument_id)
      assert is_nil(corrigido.instrument)
    end

    test "aceita tanto átomo quanto string nas chaves" do
      member = band_member_fixture(%{type: :instrumentalist, instrument: "Flauta"})
      sax = instrument_fixture("Saxofone")
      trompete = instrument_fixture("Trompete")

      assert {:ok, _} = Bands.update_member(member, %{instrument_id: sax.id})
      assert {:ok, corrigido} = Bands.update_member(member, %{"instrument_id" => trompete.id})
      assert corrigido.instrument.name == "Trompete"
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

  describe "a regra do elenco, nas três implementações" do
    # "O Líder de Banda entra no elenco mesmo sem vínculo" está escrita três
    # vezes, em duas linguagens: no SQL de `list_bands/0`, no Elixir de
    # `list_roster/1` e no de `list_bands_by_user/1`. A versão em SQL existe
    # por um bom motivo — sem ela a lista de bandas seria uma consulta por
    # linha —, então o que falta não é apagar cópia, é a trava que impede as
    # três de discordarem sem ninguém notar.
    setup do
      com_vinculo = member_fixture(%{name: "Ana Líder"})
      sem_vinculo = member_fixture(%{name: "Bruno Líder"})
      sozinho = member_fixture(%{name: "Carla Líder"})
      musico = member_fixture(%{name: "Diego Músico"})

      com_banda = band_fixture(%{leader: com_vinculo})

      band_member_fixture(%{
        band: com_banda,
        user: com_vinculo,
        type: :vocalist,
        voice_part: "Tenor"
      })

      band_member_fixture(%{band: com_banda, user: musico})

      sem_banda = band_fixture(%{leader: sem_vinculo})
      band_member_fixture(%{band: sem_banda, user: musico})

      band_fixture(%{leader: sozinho})

      %{gente: [com_vinculo, sem_vinculo, sozinho, musico]}
    end

    test "a contagem da lista de bandas bate com o elenco de cada uma" do
      bandas = Bands.list_bands()

      # Líder com vínculo, líder sem vínculo e banda só com o líder: os três
      # casos que a regra distingue.
      assert bandas |> Enum.map(& &1.roster_count) |> Enum.sort() == [1, 2, 2]

      for band <- bandas do
        assert band.roster_count == length(Bands.list_roster(band))
      end
    end

    test "estar no elenco de uma banda é o mesmo que ela estar nas bandas da pessoa", %{
      gente: gente
    } do
      pelos_elencos =
        for band <- Bands.list_bands(),
            entry <- Bands.list_roster(band),
            do: {entry.user.id, band.id}

      for pessoa <- gente do
        pelo_elenco =
          pelos_elencos |> Enum.filter(&(elem(&1, 0) == pessoa.id)) |> Enum.map(&elem(&1, 1))

        pelas_bandas = pessoa |> Bands.list_user_bands() |> Enum.map(& &1.band.id)

        assert Enum.sort(pelo_elenco) == Enum.sort(pelas_bandas)
      end
    end
  end

  describe "list_user_bands/1" do
    test "devolve as bandas do músico com a função de cada uma" do
      user = member_fixture()
      jovem = band_fixture(%{name: "Banda Jovem"})
      domingo = band_fixture(%{name: "Banda Domingo"})

      band_member_fixture(%{band: jovem, user: user, type: :instrumentalist, instrument: "Baixo"})
      band_member_fixture(%{band: domingo, user: user, type: :vocalist, voice_part: "Tenor"})

      assert [domingo_entry, jovem_entry] = Bands.list_user_bands(user)

      assert domingo_entry.band.id == domingo.id
      assert domingo_entry.member.type == :vocalist
      refute domingo_entry.leader?

      assert jovem_entry.band.id == jovem.id
      assert jovem_entry.member.instrument.name == "Baixo"
      refute jovem_entry.leader?
    end

    test "marca como líder a banda que o usuário lidera" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      band_member_fixture(%{
        band: band,
        user: leader,
        type: :instrumentalist,
        instrument: "Violão"
      })

      assert [entry] = Bands.list_user_bands(leader)
      assert entry.leader?
      assert entry.member.instrument.name == "Violão"
    end

    test "inclui a banda liderada mesmo sem vínculo, com member nil" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})

      assert [entry] = Bands.list_user_bands(leader)
      assert entry.band.id == band.id
      assert entry.leader?
      assert is_nil(entry.member)
    end

    test "não repete a banda liderada quando o líder já tem vínculo" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      band_member_fixture(%{band: band, user: leader})

      assert [entry] = Bands.list_user_bands(leader)
      assert entry.band.id == band.id
    end

    test "devolve lista vazia para quem não toca em banda nenhuma" do
      assert Bands.list_user_bands(member_fixture()) == []
    end

    test "aceita o id do usuário" do
      user = member_fixture()
      band_member_fixture(%{user: user})

      assert [_entry] = Bands.list_user_bands(user.id)
    end
  end

  describe "list_bands_by_user/1" do
    test "responde por várias pessoas de uma vez, cada uma com as suas bandas" do
      carla = member_fixture(%{name: "Carla"})
      bruno = member_fixture(%{name: "Bruno"})
      jovem = band_fixture(%{leader: carla, name: "Banda Jovem"})
      culto = band_fixture(%{name: "Banda do Culto"})

      band_member_fixture(%{band: culto, user: bruno, type: :vocalist, voice_part: "Tenor"})

      bandas = Bands.list_bands_by_user([carla.id, bruno.id])

      assert [%{band: %{id: jovem_id}, leader?: true, member: nil}] = bandas[carla.id]
      assert jovem_id == jovem.id

      assert [%{band: %{id: culto_id}, leader?: false, member: member}] = bandas[bruno.id]
      assert culto_id == culto.id
      assert member.voice_part == "Tenor"
    end

    test "quem não toca em banda nenhuma não aparece no mapa" do
      user = member_fixture()

      assert Bands.list_bands_by_user([user.id]) == %{}
    end

    test "o líder com vínculo aparece uma vez só, com a função dele" do
      leader = member_fixture()
      band = band_fixture(%{leader: leader})
      band_member_fixture(%{band: band, user: leader, instrument: "Violão"})

      assert [entry] = Bands.list_bands_by_user([leader.id])[leader.id]
      assert entry.leader?
      assert entry.member.instrument.name == "Violão"
    end

    test "ordena as bandas de cada pessoa pelo nome" do
      user = member_fixture()
      band_member_fixture(%{band: band_fixture(%{name: "Zeta"}), user: user})
      band_member_fixture(%{band: band_fixture(%{name: "Alfa"}), user: user})

      assert ["Alfa", "Zeta"] =
               Bands.list_bands_by_user([user.id])[user.id] |> Enum.map(& &1.band.name)
    end

    test "lista vazia de pessoas devolve mapa vazio" do
      band_member_fixture()

      assert Bands.list_bands_by_user([]) == %{}
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

  describe "list_instruments/0" do
    # A ordem é a do banco, e é ela que se quer: a collation do PostgreSQL lê
    # "Violão" antes de "Violino", como um leitor brasileiro leria. Ordenar em
    # Elixir compararia codepoints e poria o acento no fim, então o esperado
    # aqui é escrito por extenso em vez de derivado de um `Enum.sort/1`.
    test "traz o catálogo inteiro em ordem alfabética que ignora maiúsculas" do
      instrument_fixture("aBaFador")

      assert Enum.map(Bands.list_instruments(), & &1.name) ==
               ~w(aBaFador Baixo Bateria Flauta Guitarra Percussão Piano Saxofone Teclado
                  Trompete Violão Violino)
    end

    test "os onze iniciais nascem cadastrados e ativos" do
      catalogo = Bands.list_instruments()

      for nome <- ~w(Violão Guitarra Baixo Bateria Teclado Piano Percussão Saxofone Trompete
                     Violino Flauta) do
        assert %Instrument{active: true} = Enum.find(catalogo, &(&1.name == nome))
      end
    end

    test "conta quantos integrantes tocam cada instrumento" do
      band = band_fixture()
      band_member_fixture(%{band: band, instrument: "Bateria"})
      band_member_fixture(%{band: band, instrument: "Bateria"})
      band_member_fixture(%{band: band, instrument: "Flauta"})

      contagem = Map.new(Bands.list_instruments(), &{&1.name, &1.member_count})

      assert contagem["Bateria"] == 2
      assert contagem["Flauta"] == 1
      assert contagem["Trompete"] == 0
    end

    test "o instrumento desativado continua no catálogo" do
      trompete = instrument_fixture("Trompete")
      {:ok, _} = Bands.set_instrument_active(trompete, false)

      assert %Instrument{active: false} =
               Enum.find(Bands.list_instruments(), &(&1.id == trompete.id))
    end
  end

  describe "list_active_instruments/1" do
    test "devolve só os ativos, em ordem alfabética" do
      trompete = instrument_fixture("Trompete")
      {:ok, _} = Bands.set_instrument_active(trompete, false)

      assert Enum.map(Bands.list_active_instruments(), & &1.name) ==
               ~w(Baixo Bateria Flauta Guitarra Percussão Piano Saxofone Teclado Violão Violino)
    end

    test "o instrumento que a pessoa já toca entra mesmo desativado, na posição alfabética" do
      trompete = instrument_fixture("Trompete")
      {:ok, trompete} = Bands.set_instrument_active(trompete, false)

      assert Enum.map(Bands.list_active_instruments(trompete), & &1.name) ==
               ~w(Baixo Bateria Flauta Guitarra Percussão Piano Saxofone Teclado Trompete
                  Violão Violino)
    end

    test "instrumento ativo passado como atual não aparece duas vezes" do
      bateria = instrument_fixture("Bateria")

      nomes = Enum.map(Bands.list_active_instruments(bateria), & &1.name)

      assert Enum.count(nomes, &(&1 == "Bateria")) == 1
    end
  end

  describe "get_instrument/1" do
    test "busca pelo id, aceitando texto vindo da rota" do
      instrument = instrument_fixture("Cavaquinho")

      assert Bands.get_instrument(instrument.id).name == "Cavaquinho"
      assert Bands.get_instrument(to_string(instrument.id)).name == "Cavaquinho"
    end

    test "devolve nil para id inexistente ou inválido" do
      assert Bands.get_instrument(0) == nil
      assert Bands.get_instrument("abc") == nil
      assert Bands.get_instrument("12abc") == nil
    end
  end

  describe "create_instrument/1" do
    test "cadastra o instrumento já ativo" do
      assert {:ok, %Instrument{} = instrument} = Bands.create_instrument(%{name: "Cajón"})

      assert instrument.name == "Cajón"
      assert instrument.active
    end

    test "remove os espaços das pontas do nome" do
      assert {:ok, instrument} = Bands.create_instrument(%{name: "  Cavaquinho  "})
      assert instrument.name == "Cavaquinho"
    end

    test "exige o nome" do
      assert {:error, changeset} = Bands.create_instrument(%{})
      assert %{name: ["informe o nome do instrumento"]} = errors_on(changeset)
    end

    test "recusa nome com menos de dois ou mais de sessenta caracteres" do
      assert {:error, curto} = Bands.create_instrument(%{name: "a"})
      assert %{name: ["precisa ter entre 2 e 60 caracteres"]} = errors_on(curto)

      assert {:error, longo} = Bands.create_instrument(%{name: String.duplicate("a", 61)})
      assert %{name: ["precisa ter entre 2 e 60 caracteres"]} = errors_on(longo)
    end

    test "recusa nome repetido, sem distinguir maiúsculas" do
      assert {:error, changeset} = Bands.create_instrument(%{name: "bateria"})
      assert %{name: ["já existe um instrumento com esse nome"]} = errors_on(changeset)
    end

    test "acento distingue: Violao não colide com Violão" do
      assert {:ok, instrument} = Bands.create_instrument(%{name: "Violao"})
      assert instrument.name == "Violao"
    end
  end

  describe "update_instrument/2" do
    test "renomear vale para todos os integrantes que tocam o instrumento" do
      band = band_fixture()
      member = band_member_fixture(%{band: band, instrument: "Teclado"})
      teclado = Bands.get_instrument(member.instrument_id)

      assert {:ok, _} = Bands.update_instrument(teclado, %{name: "Teclado 88 teclas"})

      assert [atualizado] = Bands.list_members(band)
      assert atualizado.id == member.id
      assert BandMember.role_label(atualizado) == "Teclado 88 teclas"
    end

    test "corrigir a grafia do próprio instrumento não colide consigo mesmo" do
      violao = instrument_fixture("Violao")

      assert {:ok, corrigido} = Bands.update_instrument(violao, %{name: "Violao "})
      assert corrigido.name == "Violao"
    end

    test "recusa renomear para um nome que já existe" do
      piano = instrument_fixture("Piano")

      assert {:error, changeset} = Bands.update_instrument(piano, %{name: "bateria"})
      assert %{name: ["já existe um instrumento com esse nome"]} = errors_on(changeset)
    end
  end

  describe "set_instrument_active/2" do
    test "desativa e reativa sem tocar em quem já usa o instrumento" do
      band = band_fixture()
      member = band_member_fixture(%{band: band, instrument: "Trompete"})
      trompete = Bands.get_instrument(member.instrument_id)

      assert {:ok, desativado} = Bands.set_instrument_active(trompete, false)
      refute desativado.active
      assert [intacto] = Bands.list_members(band)
      assert BandMember.role_label(intacto) == "Trompete"

      assert {:ok, reativado} = Bands.set_instrument_active(desativado, true)
      assert reativado.active
    end
  end

  describe "delete_instrument/1" do
    test "exclui o instrumento que ninguém toca" do
      cajon = instrument_fixture("Cajón")

      assert {:ok, _} = Bands.delete_instrument(cajon)
      assert Bands.get_instrument(cajon.id) == nil
    end

    test "recusa o instrumento em uso, dizendo quantos o tocam" do
      band = band_fixture()
      member = band_member_fixture(%{band: band, instrument: "Bateria"})
      band_member_fixture(%{band: band_fixture(), instrument: "Bateria"})
      bateria = Bands.get_instrument(member.instrument_id)

      assert {:error, {:in_use, 2}} = Bands.delete_instrument(bateria)
      assert Bands.get_instrument(bateria.id)
    end
  end

  describe "change_instrument/2" do
    test "devolve o changeset que alimenta o formulário" do
      assert %Ecto.Changeset{} = Bands.change_instrument()
      assert %Ecto.Changeset{} = Bands.change_instrument(instrument_fixture("Cajón"))
    end
  end

  # A ordem alfabética não vem mais de um `ORDER BY` no banco: a collation muda
  # com o locale de quem o subiu, e a mesma lista aparecia em ordens diferentes
  # conforme o ambiente. Cada lista do contexto tem aqui o nome acentuado que
  # provava o defeito.
  describe "ordem alfabética das listas" do
    test "list_bands/0 põe a banda acentuada no lugar em que se lê" do
      for nome <- ~w(Zeta Alfa Ação Ana) do
        band_fixture(%{name: "Banda #{nome}"})
      end

      assert Enum.map(Bands.list_bands(), & &1.name) ==
               ["Banda Ação", "Banda Alfa", "Banda Ana", "Banda Zeta"]
    end

    test "list_leader_candidates/0 ordena os nomes acentuados junto dos outros" do
      for nome <- ~w(Zeca André Ângela Bruno) do
        member_fixture(%{name: nome})
      end

      nomes = Enum.map(Bands.list_leader_candidates(), & &1.name)

      assert Enum.filter(nomes, &(&1 in ~w(Zeca André Ângela Bruno))) ==
               ~w(André Ângela Bruno Zeca)
    end

    test "list_member_candidates/2 segue a mesma ordem" do
      band = band_fixture()

      for nome <- ~w(Zeca André Ângela Bruno) do
        member_fixture(%{name: nome})
      end

      nomes = Enum.map(Bands.list_member_candidates(band), & &1.name)

      assert Enum.filter(nomes, &(&1 in ~w(Zeca André Ângela Bruno))) ==
               ~w(André Ângela Bruno Zeca)
    end

    test "list_members/1 ordena por função e, dentro dela, pelo nome" do
      band = band_fixture()

      for nome <- ~w(Zeca André Ângela) do
        band_member_fixture(%{
          band: band,
          user: member_fixture(%{name: nome}),
          type: :instrumentalist,
          instrument: "Guitarra"
        })
      end

      band_member_fixture(%{
        band: band,
        user: member_fixture(%{name: "Ana"}),
        type: :vocalist,
        voice_part: "Soprano"
      })

      # A vocalista vem depois de todos os instrumentistas, mesmo com o nome
      # que abriria a lista — a função decide primeiro.
      assert Enum.map(Bands.list_members(band), & &1.user.name) ==
               ~w(André Ângela Zeca Ana)
    end

    test "list_bands_by_user/1 ordena as bandas de cada pessoa pelo nome" do
      user = member_fixture()

      for nome <- ~w(Zeta Ação Alfa) do
        band_member_fixture(%{band: band_fixture(%{name: "Banda #{nome}"}), user: user})
      end

      assert Enum.map(Bands.list_user_bands(user), & &1.band.name) ==
               ["Banda Ação", "Banda Alfa", "Banda Zeta"]
    end
  end
end
