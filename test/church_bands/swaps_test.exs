defmodule ChurchBands.SwapsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.Bands
  alias ChurchBands.Schedule
  alias ChurchBands.Swaps
  alias ChurchBands.Swaps.SwapRequest

  # O nome da banda é único no sistema (DT-4) e a suíte roda em paralelo: duas
  # "Banda A" ao mesmo tempo disputam o índice único. O sufixo mantém o nome
  # legível na asserção e deixa cada teste sozinho com as suas bandas.
  defp banda_chamada(nome, attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # O cenário dos seeds, reduzido ao que a troca precisa: o Elias toca guitarra
  # na Banda A e a Banda A tem um culto marcado; o Rafael toca guitarra na
  # Banda B e a Banda B tem outro. É o par que serve de origem e destino em
  # quase todo teste daqui.
  defp cenario do
    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = banda_chamada("Banda A")
    banda_b = banda_chamada("Banda B")

    elias_a = band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"})
    rafael_b = band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"})

    culto_a = event_fixture(%{starts_at: in_days(3)})
    culto_b = event_fixture(%{starts_at: in_days(4)})

    %{
      elias: elias,
      rafael: rafael,
      banda_a: banda_a,
      banda_b: banda_b,
      elias_a: elias_a,
      rafael_b: rafael_b,
      culto_a: culto_a,
      culto_b: culto_b,
      escala_a: event_band_fixture(%{event: culto_a, band: banda_a}),
      escala_b: event_band_fixture(%{event: culto_b, band: banda_b})
    }
  end

  describe "same_role?/2" do
    test "dois instrumentistas do mesmo instrumento fazem a mesma função" do
      banda = banda_chamada("Banda")
      outra = banda_chamada("Outra")

      um = band_member_fixture(%{band: banda, instrument: "Guitarra"})
      dois = band_member_fixture(%{band: outra, instrument: "Guitarra"})

      assert Swaps.same_role?(um, dois)
    end

    test "instrumentistas de instrumentos diferentes não" do
      banda = banda_chamada("Banda")
      outra = banda_chamada("Outra")

      guitarra = band_member_fixture(%{band: banda, instrument: "Guitarra"})
      baixo = band_member_fixture(%{band: outra, instrument: "Baixo"})

      refute Swaps.same_role?(guitarra, baixo)
    end

    test "duas vocalistas do mesmo naipe fazem a mesma função" do
      banda = banda_chamada("Banda")
      outra = banda_chamada("Outra")

      uma = band_member_fixture(%{band: banda, type: :vocalist, voice_part: "Soprano"})
      duas = band_member_fixture(%{band: outra, type: :vocalist, voice_part: "Soprano"})

      assert Swaps.same_role?(uma, duas)
    end

    test "vocalistas de naipes diferentes não" do
      banda = banda_chamada("Banda")
      outra = banda_chamada("Outra")

      soprano = band_member_fixture(%{band: banda, type: :vocalist, voice_part: "Soprano"})
      baixo = band_member_fixture(%{band: outra, type: :vocalist, voice_part: "Baixo"})

      refute Swaps.same_role?(soprano, baixo)
    end

    test "instrumentista e vocalista nunca trocam entre si" do
      banda = banda_chamada("Banda")
      outra = banda_chamada("Outra")

      guitarra = band_member_fixture(%{band: banda, instrument: "Guitarra"})
      soprano = band_member_fixture(%{band: outra, type: :vocalist, voice_part: "Soprano"})

      refute Swaps.same_role?(guitarra, soprano)
      refute Swaps.same_role?(soprano, guitarra)
    end
  end

  describe "shares_role?/2" do
    test "quem toca a mesma função em alguma banda faz a mesma função do alvo" do
      %{elias: elias, rafael_b: rafael_b} = cenario()

      assert Swaps.shares_role?(elias, rafael_b)
    end

    test "quem só canta não faz a função de um guitarrista" do
      %{rafael_b: rafael_b} = cenario()

      vocalista = member_fixture()

      band_member_fixture(%{
        band: banda_chamada("Coral"),
        user: vocalista,
        type: :vocalist,
        voice_part: "Soprano"
      })

      refute Swaps.shares_role?(vocalista, rafael_b)
    end

    test "quem não está em banda nenhuma não faz função nenhuma" do
      %{rafael_b: rafael_b} = cenario()

      refute Swaps.shares_role?(member_fixture(), rafael_b)
    end
  end

  describe "list_origin_options/2" do
    test "oferece o evento futuro em que a pessoa toca a mesma função do alvo" do
      %{elias: elias, rafael_b: rafael_b, escala_a: escala_a, elias_a: elias_a} = cenario()

      assert [origem] = Swaps.list_origin_options(elias, rafael_b)
      assert origem.event_band.id == escala_a.id
      assert origem.member.id == elias_a.id
      assert origem.event_band.band.name =~ "Banda A"
    end

    test "não oferece o evento do próprio alvo: ele está escalado lá" do
      %{elias: elias, banda_a: banda_a, rafael_b: rafael_b, culto_b: culto_b} = cenario()

      # A Banda A também toca no culto da Banda B — e mesmo assim aquele dia
      # não serve de origem, porque o Rafael vai estar lá de qualquer jeito.
      event_band_fixture(%{event: culto_b, band: banda_a})

      ids = Enum.map(Swaps.list_origin_options(elias, rafael_b), & &1.event.id)

      refute culto_b.id in ids
    end

    test "não oferece o evento em que o alvo já toca por outra banda" do
      %{elias: elias, rafael: rafael, rafael_b: rafael_b, culto_a: culto_a} = cenario()

      terceira = banda_chamada("Banda C")
      band_member_fixture(%{band: terceira, user: rafael, instrument: "Guitarra"})
      event_band_fixture(%{event: culto_a, band: terceira})

      assert Swaps.list_origin_options(elias, rafael_b) == []
    end

    test "não oferece o evento em que o alvo lidera a banda escalada, mesmo sem vínculo" do
      %{elias: elias, rafael: rafael, rafael_b: rafael_b, culto_a: culto_a} = cenario()

      liderada = banda_chamada("Banda do Rafael", %{leader: rafael})
      event_band_fixture(%{event: culto_a, band: liderada})

      assert Swaps.list_origin_options(elias, rafael_b) == []
    end

    test "não oferece evento cancelado nem evento que já passou" do
      %{elias: elias, banda_a: banda_a, rafael_b: rafael_b, culto_a: culto_a} = cenario()

      passado = event_fixture(%{starts_at: in_days(-3)})
      event_band_fixture(%{event: passado, band: banda_a})
      {:ok, _} = Schedule.cancel_event(culto_a)

      assert Swaps.list_origin_options(elias, rafael_b) == []
    end

    test "ordena do compromisso mais próximo ao mais distante" do
      %{elias: elias, banda_a: banda_a, rafael_b: rafael_b, culto_a: culto_a} = cenario()

      depois = event_fixture(%{starts_at: in_days(20)})
      antes = event_fixture(%{starts_at: in_days(1)})
      event_band_fixture(%{event: depois, band: banda_a})
      event_band_fixture(%{event: antes, band: banda_a})

      ids = Enum.map(Swaps.list_origin_options(elias, rafael_b), & &1.event.id)

      assert ids == [antes.id, culto_a.id, depois.id]
    end

    test "quem não faz a função do alvo não tem origem nenhuma" do
      %{elias: elias, banda_b: banda_b} = cenario()

      soprano =
        band_member_fixture(%{band: banda_b, type: :vocalist, voice_part: "Soprano"})

      assert Swaps.list_origin_options(elias, soprano) == []
    end
  end

  describe "requestable_member_ids/2" do
    test "traz quem faz a mesma função em outra banda escalada naquele evento" do
      %{elias: elias, rafael_b: rafael_b, culto_b: culto_b, banda_b: banda_b} = cenario()

      band_member_fixture(%{band: banda_b, type: :vocalist, voice_part: "Soprano"})
      band_member_fixture(%{band: banda_b, instrument: "Baixo"})

      assert Swaps.requestable_member_ids(elias, culto_b) == MapSet.new([rafael_b.id])
    end

    test "não traz você mesmo, nem quando você toca no evento aberto" do
      %{elias: elias, elias_a: elias_a, culto_a: culto_a, banda_a: banda_a, culto_b: culto_b} =
        cenario()

      # Outro guitarrista da própria banda também não serve: ele já vai estar
      # no mesmo culto que você quer largar.
      colega = band_member_fixture(%{band: banda_a, instrument: "Guitarra"})
      event_band_fixture(%{event: culto_b, band: banda_a})

      requestable = Swaps.requestable_member_ids(elias, culto_a)

      refute MapSet.member?(requestable, elias_a.id)
      refute MapSet.member?(requestable, colega.id)
    end

    test "não traz o Líder de Banda sem vínculo: sem função não há com o que casar" do
      %{elias: elias, rafael_b: rafael_b, culto_b: culto_b, banda_b: banda_b} = cenario()

      # A Sofia dos seeds: lidera a banda sem vínculo, então aparece no elenco
      # com `member: nil` — e não sobra id nenhum dela para ser alvo.
      assert Enum.any?(Bands.list_roster(banda_b), &(&1.leader? and is_nil(&1.member)))
      assert Swaps.requestable_member_ids(elias, culto_b) == MapSet.new([rafael_b.id])
    end

    test "evento cancelado e evento que já passou não têm alvo nenhum" do
      %{elias: elias, banda_b: banda_b, culto_b: culto_b} = cenario()

      {:ok, cancelado} = Schedule.cancel_event(culto_b)
      passado = event_fixture(%{starts_at: in_days(-2)})
      event_band_fixture(%{event: passado, band: banda_b})

      assert Swaps.requestable_member_ids(elias, cancelado) == MapSet.new()
      assert Swaps.requestable_member_ids(elias, passado) == MapSet.new()
    end

    test "quem não está escalado em evento futuro nenhum não pode pedir a ninguém" do
      %{culto_b: culto_b} = cenario()

      assert Swaps.requestable_member_ids(member_fixture(), culto_b) == MapSet.new()
    end

    test "o elenco inteiro sai de três consultas, e não de uma por integrante" do
      %{elias: elias, banda_b: banda_b, culto_b: culto_b} = cenario()

      for _ <- 1..5, do: band_member_fixture(%{band: banda_b, instrument: "Guitarra"})

      ids = assert_queries(3, fn -> Swaps.requestable_member_ids(elias, culto_b) end)

      assert MapSet.size(ids) == 6
    end

    test "quem não tem escala futura custa uma consulta só: não há o que perguntar" do
      %{culto_b: culto_b} = cenario()

      sem_escala = member_fixture()

      assert_queries(1, fn -> Swaps.requestable_member_ids(sem_escala, culto_b) end)
    end
  end

  describe "can_request?/3" do
    test "responde o mesmo que a lista de alvos daquele evento" do
      %{elias: elias, rafael_b: rafael_b, elias_a: elias_a, culto_b: culto_b, culto_a: culto_a} =
        cenario()

      assert Swaps.can_request?(elias, culto_b, rafael_b)
      refute Swaps.can_request?(elias, culto_a, elias_a)
    end
  end

  describe "request_swap/4" do
    test "cria o pedido pendente com as duas escalas e os dois vínculos" do
      %{
        elias: elias,
        rafael_b: rafael_b,
        elias_a: elias_a,
        escala_a: escala_a,
        escala_b: escala_b,
        culto_b: culto_b
      } = cenario()

      assert {:ok, pedido} =
               Swaps.request_swap(elias, culto_b, rafael_b, to_string(escala_a.id))

      assert pedido.status == :pending
      assert pedido.requester_event_band_id == escala_a.id
      assert pedido.requester_member_id == elias_a.id
      assert pedido.target_event_band_id == escala_b.id
      assert pedido.target_member_id == rafael_b.id
    end

    test "entrega ao alvo o e-mail com o link de /swaps, e sem token" do
      %{elias: elias, rafael: rafael, rafael_b: rafael_b, escala_a: escala_a, culto_b: culto_b} =
        cenario()

      assert {:ok, _pedido} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)

      assert_email_sent(fn email ->
        assert {_, endereco} = hd(email.to)
        assert endereco == rafael.email
        assert email.subject == "Pedido de troca de escala"
        assert email.text_body =~ "Elias Guitarrista"
        assert email.text_body =~ "/swaps"
      end)
    end

    test "recusa alvo de função diferente" do
      %{elias: elias, banda_b: banda_b, escala_a: escala_a, culto_b: culto_b} = cenario()

      baixo = band_member_fixture(%{band: banda_b, instrument: "Baixo"})

      assert {:error, :ineligible} = Swaps.request_swap(elias, culto_b, baixo, escala_a.id)
    end

    test "recusa pedir troca a si mesmo" do
      %{elias: elias, elias_a: elias_a, escala_a: escala_a, culto_a: culto_a} = cenario()

      assert {:error, :ineligible} = Swaps.request_swap(elias, culto_a, elias_a, escala_a.id)
    end

    test "recusa quando o evento do alvo já passou ou foi cancelado" do
      %{elias: elias, rafael_b: rafael_b, escala_a: escala_a, culto_b: culto_b} = cenario()

      {:ok, cancelado} = Schedule.cancel_event(culto_b)

      assert {:error, :ineligible} =
               Swaps.request_swap(elias, cancelado, rafael_b, escala_a.id)
    end

    test "recusa quando o alvo já está escalado no evento de origem" do
      %{
        elias: elias,
        rafael: rafael,
        rafael_b: rafael_b,
        escala_a: escala_a,
        culto_a: culto_a,
        culto_b: culto_b
      } = cenario()

      terceira = banda_chamada("Banda C")
      band_member_fixture(%{band: terceira, user: rafael, instrument: "Guitarra"})
      event_band_fixture(%{event: culto_a, band: terceira})

      assert {:error, :ineligible} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)
    end

    test "recusa a origem forjada: um evento em que a pessoa não está escalada" do
      %{elias: elias, rafael_b: rafael_b, culto_b: culto_b, banda_b: banda_b} = cenario()

      alheio = event_fixture(%{starts_at: in_days(5)})
      escala_alheia = event_band_fixture(%{event: alheio, band: banda_b})

      assert {:error, :ineligible} =
               Swaps.request_swap(elias, culto_b, rafael_b, escala_alheia.id)
    end

    test "recusa o próprio evento do alvo como origem" do
      %{elias: elias, rafael_b: rafael_b, escala_b: escala_b, culto_b: culto_b} = cenario()

      assert {:error, :ineligible} = Swaps.request_swap(elias, culto_b, rafael_b, escala_b.id)
    end

    test "recusa o que veio no lugar do id da origem e não é um id" do
      %{elias: elias, rafael_b: rafael_b, culto_b: culto_b} = cenario()

      assert {:error, :ineligible} = Swaps.request_swap(elias, culto_b, rafael_b, "banana")
    end

    test "recusa o segundo pedido pendente para o mesmo evento de origem" do
      %{elias: elias, rafael_b: rafael_b, escala_a: escala_a, culto_b: culto_b, banda_b: banda_b} =
        cenario()

      outro = band_member_fixture(%{band: banda_b, instrument: "Guitarra"})

      assert {:ok, _} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)

      assert {:error, changeset} = Swaps.request_swap(elias, culto_b, outro, escala_a.id)

      assert "Você já tem um pedido de troca pendente para este evento." in errors_on(changeset).requester_event_band_id
    end

    test "aceita pedidos pendentes em eventos de origem diferentes" do
      %{elias: elias, rafael_b: rafael_b, escala_a: escala_a, banda_a: banda_a, culto_b: culto_b} =
        cenario()

      ensaio = event_fixture(%{starts_at: in_days(2)})
      escala_ensaio = event_band_fixture(%{event: ensaio, band: banda_a})

      assert {:ok, _} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)
      assert {:ok, _} = Swaps.request_swap(elias, culto_b, rafael_b, escala_ensaio.id)
    end

    test "o pedido cancelado libera a vaga para um pedido novo" do
      %{elias: elias, rafael_b: rafael_b, escala_a: escala_a, culto_b: culto_b} = cenario()

      {:ok, pedido} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)
      {:ok, _} = Swaps.cancel_request(elias, pedido)

      assert {:ok, _} = Swaps.request_swap(elias, culto_b, rafael_b, escala_a.id)
    end
  end

  describe "cancel_request/2" do
    test "o solicitante cancela o pedido pendente e o alvo é avisado por e-mail" do
      %{elias: elias, rafael: rafael} = ctx = pedido_feito()

      assert {:ok, cancelado} = Swaps.cancel_request(elias, ctx.pedido)
      assert cancelado.status == :cancelled

      assert_email_sent(fn email ->
        assert {_, endereco} = hd(email.to)
        assert endereco == rafael.email
        assert email.subject == "Pedido de troca cancelado"
      end)
    end

    test "o alvo não cancela o pedido que recebeu" do
      %{rafael: rafael, pedido: pedido} = pedido_feito()

      assert {:error, :ineligible} = Swaps.cancel_request(rafael, pedido)
      assert Swaps.get_request(pedido.id).status == :pending
    end

    test "pedido já cancelado não é cancelado de novo" do
      %{elias: elias, pedido: pedido} = pedido_feito()

      {:ok, cancelado} = Swaps.cancel_request(elias, pedido)

      assert {:error, :ineligible} = Swaps.cancel_request(elias, Swaps.get_request(cancelado.id))
    end
  end

  describe "a vaga que some leva o pedido junto" do
    test "desescalar a banda do alvo apaga o pedido" do
      %{pedido: pedido, escala_b: escala_b} = pedido_feito()

      {:ok, _} = Schedule.unschedule_band(escala_b)

      assert Swaps.get_request(pedido.id) == nil
    end

    test "desescalar a banda de origem apaga o pedido" do
      %{pedido: pedido, escala_a: escala_a} = pedido_feito()

      {:ok, _} = Schedule.unschedule_band(escala_a)

      assert Swaps.get_request(pedido.id) == nil
    end

    test "tirar o alvo da banda apaga o pedido" do
      %{pedido: pedido, rafael_b: rafael_b} = pedido_feito()

      {:ok, _} = Bands.remove_member(rafael_b)

      assert Swaps.get_request(pedido.id) == nil
    end

    test "cancelar o evento de origem não apaga o pedido: ele continua pendente" do
      %{pedido: pedido, culto_a: culto_a} = pedido_feito()

      {:ok, _} = Schedule.cancel_event(culto_a)

      assert Swaps.get_request(pedido.id).status == :pending
    end
  end

  describe "list_sent/1 e list_received/1" do
    test "cada um vê os seus dois lados do mesmo pedido" do
      %{elias: elias, rafael: rafael, pedido: pedido} = pedido_feito()

      assert [enviado] = Swaps.list_sent(elias)
      assert enviado.id == pedido.id
      assert Swaps.list_received(elias) == []

      assert [recebido] = Swaps.list_received(rafael)
      assert recebido.id == pedido.id
      assert Swaps.list_sent(rafael) == []
    end

    test "trazem os quatro nomes já pré-carregados, numa consulta cada" do
      %{elias: elias} = pedido_feito()

      [enviado] = assert_queries(1, fn -> Swaps.list_sent(elias) end)

      assert enviado.requester_member.user.name == "Elias Guitarrista"
      assert enviado.target_member.user.name == "Rafael Guitarrista"
      assert enviado.requester_member.instrument.name == "Guitarra"
      assert enviado.requester_event_band.event.title
      assert enviado.requester_event_band.band.name =~ "Banda A"
      assert enviado.target_event_band.event.title
      assert enviado.target_event_band.band.name =~ "Banda B"
    end

    test "trazem a vocalista sem instrumento, que o left_join deixa passar" do
      elias = member_fixture()
      julia = member_fixture()

      banda_a = banda_chamada("Banda A")
      banda_b = banda_chamada("Banda B")

      elias_a =
        band_member_fixture(%{band: banda_a, user: elias, type: :vocalist, voice_part: "Soprano"})

      julia_b =
        band_member_fixture(%{band: banda_b, user: julia, type: :vocalist, voice_part: "Soprano"})

      culto_a = event_fixture(%{starts_at: in_days(3)})
      culto_b = event_fixture(%{starts_at: in_days(4)})

      swap_request_fixture(%{
        requester_event_band: event_band_fixture(%{event: culto_a, band: banda_a}),
        requester_member: elias_a,
        target_event_band: event_band_fixture(%{event: culto_b, band: banda_b}),
        target_member: julia_b
      })

      assert [enviado] = Swaps.list_sent(elias)
      assert enviado.requester_member.instrument == nil
      assert enviado.requester_member.voice_part == "Soprano"
    end

    test "do mais recente ao mais antigo" do
      ctx = pedido_feito()

      segundo =
        swap_request_fixture(%{
          requester_event_band: ctx.escala_a,
          requester_member: ctx.elias_a,
          target_event_band: ctx.escala_b,
          target_member: ctx.rafael_b,
          status: :cancelled
        })

      assert [primeiro, ultimo] = Swaps.list_sent(ctx.elias)
      assert primeiro.id == segundo.id
      assert ultimo.id == ctx.pedido.id
    end

    test "ninguém vê os pedidos dos outros, nem quem tem acesso total" do
      pedido_feito()

      pastor = pastor_fixture()

      assert Swaps.list_sent(pastor) == []
      assert Swaps.list_received(pastor) == []
    end
  end

  describe "get_request/1" do
    test "busca pelo id, com as duas escalas e os dois vínculos" do
      %{pedido: pedido} = pedido_feito()

      assert %SwapRequest{} = encontrado = Swaps.get_request(to_string(pedido.id))
      assert encontrado.target_member.user.name == "Rafael Guitarrista"
    end

    test "devolve nil para o que não é um id e para o id que não existe" do
      assert Swaps.get_request("banana") == nil
      assert Swaps.get_request(0) == nil
    end
  end

  # O cenário com o pedido já feito, que é o ponto de partida de cancelar,
  # listar e apagar.
  defp pedido_feito do
    ctx = cenario()

    pedido =
      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b
      })

    Map.put(ctx, :pedido, Swaps.get_request(pedido.id))
  end
end
