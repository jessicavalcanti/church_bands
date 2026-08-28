defmodule ChurchBands.SwapsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.Bands
  alias ChurchBands.Notifications
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

  describe "list_pending_for_user/1" do
    test "o mesmo pedido é ação de um lado e espera do outro" do
      %{elias: elias, rafael: rafael, pedido: pedido} = pedido_feito()

      assert %{received: [], sent: [esperando]} = Swaps.list_pending_for_user(elias)
      assert esperando.id == pedido.id

      assert %{received: [para_responder], sent: []} = Swaps.list_pending_for_user(rafael)
      assert para_responder.id == pedido.id
    end

    test "traz os quatro nomes já pré-carregados, numa consulta" do
      %{rafael: rafael} = pedido_feito()

      resultado = assert_queries(1, fn -> Swaps.list_pending_for_user(rafael) end)

      assert %{received: [recebido]} = resultado
      assert recebido.requester_member.user.name == "Elias Guitarrista"
      assert recebido.target_member.user.name == "Rafael Guitarrista"
      assert recebido.requester_member.instrument.name == "Guitarra"
      assert recebido.requester_event_band.event.title
      assert recebido.requester_event_band.band.name =~ "Banda A"
      assert recebido.target_event_band.event.title
      assert recebido.target_event_band.band.name =~ "Banda B"
    end

    test "cinco pedidos custam a mesma consulta que um" do
      ctx = cenario()
      rafael_b = ctx.rafael_b

      for _ <- 1..5 do
        banda = banda_chamada("Banda de origem")
        pedinte = member_fixture()
        vinculo = band_member_fixture(%{band: banda, user: pedinte, instrument: "Guitarra"})
        culto = event_fixture(%{starts_at: in_days(3)})

        swap_request_fixture(%{
          requester_event_band: event_band_fixture(%{event: culto, band: banda}),
          requester_member: vinculo,
          target_event_band: ctx.escala_b,
          target_member: rafael_b
        })
      end

      resultado = assert_queries(1, fn -> Swaps.list_pending_for_user(ctx.rafael) end)

      assert length(resultado.received) == 5
    end

    test "o pedido respondido sai da lista, e continua na caixa de entrada" do
      %{rafael: rafael, pedido: pedido} = pedido_feito()

      {:ok, _} = Swaps.decline_request(rafael, pedido)

      assert %{received: [], sent: []} = Swaps.list_pending_for_user(rafael)
      assert [_] = Swaps.list_received(rafael)
    end

    test "o pedido cancelado pelo solicitante também sai" do
      %{elias: elias, pedido: pedido} = pedido_feito()

      {:ok, _} = Swaps.cancel_request(elias, pedido)

      assert %{received: [], sent: []} = Swaps.list_pending_for_user(elias)
    end

    # A regra 4 da US 4.6 e a regra 3 da US 4.3 são a mesma pergunta: sem o dia
    # de quem pediu não há o que cobrir nem o que trocar, e a home é o lugar do
    # que ainda dá para resolver.
    test "o pedido cujo dia de origem foi cancelado sai dos dois lados" do
      ctx = pedido_feito()

      {:ok, _} = Schedule.cancel_event(ctx.culto_a)

      assert %{received: [], sent: []} = Swaps.list_pending_for_user(ctx.rafael)
      assert %{received: [], sent: []} = Swaps.list_pending_for_user(ctx.elias)
      assert [_] = Swaps.list_received(ctx.rafael)
    end

    test "o pedido cujo dia de origem já passou sai dos dois lados" do
      ctx = pedido_feito()

      backdate(ctx.culto_a, in_days(-1))

      assert %{received: [], sent: []} = Swaps.list_pending_for_user(ctx.rafael)
      assert %{received: [], sent: []} = Swaps.list_pending_for_user(ctx.elias)
    end

    # O dia do **alvo** cancelado não tira o pedido daqui: quem está com o
    # próprio culto cancelado ficou mais livre para cobrir o outro, e continua
    # podendo recusar. Some com a linha, e os dois lados ficam sem ação.
    test "o dia do alvo cancelado não tira o pedido: ele ainda pode ser coberto ou recusado" do
      ctx = pedido_feito()

      {:ok, _} = Schedule.cancel_event(ctx.culto_b)

      assert %{received: [recebido]} = Swaps.list_pending_for_user(ctx.rafael)
      assert recebido.id == ctx.pedido.id
      assert Swaps.respond?(ctx.rafael, ctx.pedido)
    end

    test "ninguém vê os pedidos dos outros, nem quem tem acesso total" do
      pedido_feito()

      assert %{received: [], sent: []} = Swaps.list_pending_for_user(pastor_fixture())
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

  describe "respond?/2" do
    test "o alvo responde ao pedido pendente" do
      %{rafael: rafael, pedido: pedido} = pedido_feito()

      assert Swaps.respond?(rafael, pedido)
    end

    test "o solicitante não responde ao próprio pedido" do
      %{elias: elias, pedido: pedido} = pedido_feito()

      refute Swaps.respond?(elias, pedido)
    end

    test "quem tem acesso total não responde pelo pedido dos outros" do
      %{pedido: pedido} = pedido_feito()

      refute Swaps.respond?(pastor_fixture(), pedido)
    end

    test "pedido já respondido não se responde de novo" do
      %{rafael: rafael, pedido: pedido} = troca_aceita(:cover)

      refute Swaps.respond?(rafael, pedido)
      refute Swaps.respond?(rafael, %{pedido | status: :declined})
    end

    test "não se responde a pedido cujo evento de origem foi cancelado" do
      %{rafael: rafael, pedido: pedido, culto_a: culto_a} = pedido_feito()

      {:ok, _} = Schedule.cancel_event(culto_a)

      refute Swaps.respond?(rafael, Swaps.get_request(pedido.id))
    end

    test "nem a pedido cujo evento de origem já passou" do
      %{rafael: rafael, pedido: pedido, culto_a: culto_a} = pedido_feito()

      backdate(culto_a, in_days(-1))

      refute Swaps.respond?(rafael, Swaps.get_request(pedido.id))
    end

    test "o evento do alvo cancelado não tira a resposta: quem cobre ficou mais livre" do
      %{rafael: rafael, pedido: pedido, culto_b: culto_b} = pedido_feito()

      {:ok, _} = Schedule.cancel_event(culto_b)

      assert Swaps.respond?(rafael, Swaps.get_request(pedido.id))
    end
  end

  describe "accept_request/3 em só cobrir" do
    test "o alvo assume o dia de quem pediu e avisa por e-mail" do
      %{rafael: rafael, elias: elias, pedido: pedido} = pedido_feito()

      assert {:ok, aceito} = Swaps.accept_request(rafael, pedido, "cover")
      assert aceito.status == :accepted
      assert aceito.mode == :cover
      assert aceito.responded_at

      assert_email_sent(fn email ->
        assert {_, endereco} = hd(email.to)
        assert endereco == elias.email
        assert email.subject == "Pedido de troca aceito"
        refute email.text_body =~ "E passou a tocar em:"
        assert email.text_body =~ "Você está liberado de:"
      end)
    end

    test "o elenco do evento de origem passa a mostrar quem cobre" do
      %{culto_a: culto_a, banda_a: banda_a, elias: elias, rafael: rafael} = troca_aceita(:cover)

      assert %{substitute: substituto, user: titular} =
               entrada_do_elenco(culto_a, banda_a, elias)

      assert substituto.id == rafael.id
      assert titular.id == elias.id
    end

    test "o evento do alvo não muda: ele continua escalado ali" do
      %{culto_b: culto_b, banda_b: banda_b, rafael: rafael} = troca_aceita(:cover)

      assert %{substitute: nil} = entrada_do_elenco(culto_b, banda_b, rafael)
    end

    test "nada muda em band_members" do
      ctx = cenario()

      pedido = pedido_de(ctx)
      antes = Bands.list_members(ctx.banda_a.id)

      assert {:ok, _} = Swaps.accept_request(ctx.rafael, pedido, "cover")
      assert Bands.list_members(ctx.banda_a.id) == antes
    end

    test "recusa quando o alvo ficaria com dois eventos a menos de 3 horas, e nomeia o outro" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -90, :minute)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      assert {:error, {:conflict, outro}} =
               Swaps.accept_request(ctx.rafael, pedido_de(ctx), "cover")

      assert outro.id == ensaio.id
    end

    test "a borda é aberta: exatamente 3 horas passa" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -Schedule.conflict_window_hours(), :hour)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      assert {:ok, _} = Swaps.accept_request(ctx.rafael, pedido_de(ctx), "cover")
    end

    test "o outro evento cancelado não ocupa ninguém" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -90, :minute)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})
      {:ok, _} = Schedule.cancel_event(ensaio)

      assert {:ok, _} = Swaps.accept_request(ctx.rafael, pedido_de(ctx), "cover")
    end

    test "recusa quando a vaga de origem já foi trocada por outro pedido aceito" do
      ctx = cenario()
      outro_alvo = band_member_fixture(%{band: ctx.banda_b, instrument: "Guitarra"})

      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: outro_alvo,
        status: :accepted,
        mode: :cover
      })

      assert {:error, :slot_taken} =
               Swaps.accept_request(ctx.rafael, pedido_de(ctx), "cover")
    end
  end

  describe "accept_request/3 em trocar o dia" do
    test "as duas vagas mudam de dono, e o e-mail diz qual dia quem pediu assumiu" do
      %{rafael: rafael, elias: elias, pedido: pedido, culto_b: culto_b} = pedido_feito()

      assert {:ok, aceito} = Swaps.accept_request(rafael, pedido, "swap")
      assert aceito.mode == :swap

      assert_email_sent(fn email ->
        assert email.text_body =~ "E passou a tocar em: #{culto_b.title}"
      end)

      assert %{substitute: substituto} =
               entrada_do_elenco(culto_b, hd(Bands.list_user_bands(rafael)).band, rafael)

      assert substituto.id == elias.id
    end

    test "recusa quando quem pediu já está escalado no evento do alvo" do
      ctx = cenario()
      event_band_fixture(%{event: ctx.culto_b, band: ctx.banda_a})

      assert {:error, :ineligible} = Swaps.accept_request(ctx.rafael, pedido_de(ctx), "swap")
    end

    test "recusa quando quem pediu ficaria com dois compromissos a menos de 3 horas" do
      ctx = cenario()
      outra = banda_chamada("Banda C")
      band_member_fixture(%{band: outra, user: ctx.elias, instrument: "Guitarra"})
      ensaio = evento_perto_de(ctx.culto_b, -60, :minute)
      event_band_fixture(%{event: ensaio, band: outra})

      assert {:error, {:conflict, outro}} =
               Swaps.accept_request(ctx.rafael, pedido_de(ctx), "swap")

      assert outro.id == ensaio.id
    end

    test "a vaga que quem pediu está cedendo não conta como conflito" do
      ctx = cenario()
      # Os dois cultos passam a estar a uma hora um do outro: cada um cede o
      # seu e assume o do outro, e ninguém toca duas vezes.
      perto = evento_perto_de(ctx.culto_a, 60, :minute)
      escala_perto = event_band_fixture(%{event: perto, band: ctx.banda_b})

      pedido =
        swap_request_fixture(%{
          requester_event_band: ctx.escala_a,
          requester_member: ctx.elias_a,
          target_event_band: escala_perto,
          target_member: ctx.rafael_b
        })

      assert {:ok, _} = Swaps.accept_request(ctx.rafael, Swaps.get_request(pedido.id), "swap")
    end

    test "recusa quando o alvo ficaria com dois compromissos a menos de 3 horas" do
      ctx = cenario()
      outra = banda_chamada("Banda C")
      band_member_fixture(%{band: outra, user: ctx.rafael, instrument: "Guitarra"})
      ensaio = evento_perto_de(ctx.culto_a, -60, :minute)
      event_band_fixture(%{event: ensaio, band: outra})

      assert {:error, {:conflict, outro}} =
               Swaps.accept_request(ctx.rafael, pedido_de(ctx), "swap")

      assert outro.id == ensaio.id
    end

    test "a vaga do alvo já trocada recusa o segundo pedido, mas cobrir passa" do
      ctx = cenario()
      gabriela = member_fixture(%{name: "Gabriela Guitarrista"})
      banda_c = banda_chamada("Banda C")
      gabriela_c = band_member_fixture(%{band: banda_c, user: gabriela, instrument: "Guitarra"})
      culto_c = event_fixture(%{starts_at: in_days(6)})
      escala_c = event_band_fixture(%{event: culto_c, band: banda_c})

      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b,
        status: :accepted,
        mode: :swap
      })

      segundo =
        swap_request_fixture(%{
          requester_event_band: escala_c,
          requester_member: gabriela_c,
          target_event_band: ctx.escala_b,
          target_member: ctx.rafael_b
        })

      assert {:error, :slot_taken} =
               Swaps.accept_request(ctx.rafael, Swaps.get_request(segundo.id), "swap")

      assert {:ok, aceito} =
               Swaps.accept_request(ctx.rafael, Swaps.get_request(segundo.id), "cover")

      assert aceito.mode == :cover
    end

    test "nada é gravado quando a troca é recusada dentro da transação" do
      ctx = cenario()
      event_band_fixture(%{event: ctx.culto_b, band: ctx.banda_a})
      pedido = pedido_de(ctx)

      assert {:error, :ineligible} = Swaps.accept_request(ctx.rafael, pedido, "swap")

      recarregado = Swaps.get_request(pedido.id)
      assert recarregado.status == :pending
      assert recarregado.mode == nil
      assert recarregado.responded_at == nil
      assert_no_email_sent()
    end
  end

  describe "accept_request/3, quem pode e com que modo" do
    test "o modo que não existe é recusado sem gravar nada" do
      %{rafael: rafael, pedido: pedido} = pedido_feito()

      assert {:error, :ineligible} = Swaps.accept_request(rafael, pedido, "banana")
      assert Swaps.get_request(pedido.id).status == :pending
    end

    test "o solicitante não aceita o próprio pedido" do
      %{elias: elias, pedido: pedido} = pedido_feito()

      assert {:error, :ineligible} = Swaps.accept_request(elias, pedido, "cover")
      assert Swaps.get_request(pedido.id).status == :pending
    end

    test "quem tem acesso total não aceita pelo alvo" do
      %{pedido: pedido} = pedido_feito()

      assert {:error, :ineligible} = Swaps.accept_request(pastor_fixture(), pedido, "cover")
    end

    test "com o dia do alvo cancelado, cobrir e recusar passam e trocar não" do
      ctx = cenario()
      {:ok, _} = Schedule.cancel_event(ctx.culto_b)

      pedido = pedido_de(ctx)

      assert {:error, :ineligible} = Swaps.accept_request(ctx.rafael, pedido, "swap")
      assert {:ok, %{mode: :cover}} = Swaps.accept_request(ctx.rafael, pedido, "cover")

      outro = cenario()
      {:ok, _} = Schedule.cancel_event(outro.culto_b)

      assert {:ok, %{status: :declined}} =
               Swaps.decline_request(outro.rafael, pedido_de(outro))
    end

    test "o pedido de evento de origem cancelado não é aceito" do
      %{rafael: rafael, pedido: pedido, culto_a: culto_a} = pedido_feito()

      {:ok, _} = Schedule.cancel_event(culto_a)

      assert {:error, :ineligible} =
               Swaps.accept_request(rafael, Swaps.get_request(pedido.id), "cover")
    end
  end

  describe "decline_request/2" do
    test "o alvo recusa, quem pediu é avisado e nenhuma escala muda" do
      %{rafael: rafael, elias: elias, pedido: pedido, culto_a: culto_a, banda_a: banda_a} =
        pedido_feito()

      assert {:ok, recusado} = Swaps.decline_request(rafael, pedido)
      assert recusado.status == :declined
      assert recusado.mode == nil
      assert recusado.responded_at

      assert_email_sent(fn email ->
        assert {_, endereco} = hd(email.to)
        assert endereco == elias.email
        assert email.subject == "Pedido de troca recusado"
      end)

      assert %{substitute: nil} = entrada_do_elenco(culto_a, banda_a, elias)
    end

    test "quem não é o alvo não recusa" do
      %{elias: elias, pedido: pedido} = pedido_feito()

      assert {:error, :ineligible} = Swaps.decline_request(elias, pedido)
    end

    test "pedido recusado não volta a pendente, e a vaga fica livre para um pedido novo" do
      ctx = cenario()
      pedido = pedido_de(ctx)

      {:ok, recusado} = Swaps.decline_request(ctx.rafael, pedido)

      assert {:error, :ineligible} =
               Swaps.decline_request(ctx.rafael, Swaps.get_request(recusado.id))

      assert {:ok, _} =
               Swaps.request_swap(ctx.elias, ctx.culto_b, ctx.rafael_b, ctx.escala_a.id)
    end
  end

  describe "person_busy_event/3" do
    test "acha o evento em que a pessoa toca dentro da janela" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -90, :minute)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      assert %{id: id} = ocupado_em(ctx.rafael, ctx.culto_a)
      assert id == ensaio.id
    end

    test "não acha o que está fora da janela" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -4, :hour)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      assert ocupado_em(ctx.rafael, ctx.culto_a) == nil
    end

    test "a borda é aberta: exatamente a janela não ocupa" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -Schedule.conflict_window_hours(), :hour)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      assert ocupado_em(ctx.rafael, ctx.culto_a) == nil
    end

    test "evento cancelado não ocupa ninguém" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, -90, :minute)
      event_band_fixture(%{event: ensaio, band: ctx.banda_b})
      {:ok, _} = Schedule.cancel_event(ensaio)

      assert ocupado_em(ctx.rafael, ctx.culto_a) == nil
    end

    test "o dia assumido por troca aceita conta, mesmo sem vínculo com a banda" do
      ctx = troca_aceita(:cover)
      # O Rafael assumiu o culto da Banda A, e não é membro dela: o ensaio
      # marcado 1h depois passa a ser conflito dele.
      ensaio = evento_perto_de(ctx.culto_a, 60, :minute)

      assert %{id: id} = ocupado_em(ctx.rafael, ensaio)
      assert id == ctx.culto_a.id
    end

    test "o dia cedido por troca aceita não conta" do
      ctx = troca_aceita(:swap)
      # O Rafael entregou o dia dele ao Elias: um ensaio ao lado do culto B
      # deixou de ser conflito para ele.
      ensaio = evento_perto_de(ctx.culto_b, 60, :minute)

      assert ocupado_em(ctx.rafael, ensaio) == nil
    end

    test "em só cobrir, o dia do alvo continua sendo dele" do
      ctx = troca_aceita(:cover)
      ensaio = evento_perto_de(ctx.culto_b, 60, :minute)

      assert %{id: id} = ocupado_em(ctx.rafael, ensaio)
      assert id == ctx.culto_b.id
    end

    test ":releasing tira a vaga que este pedido ainda vai ceder" do
      ctx = cenario()
      ensaio = evento_perto_de(ctx.culto_a, 60, :minute)

      assert ocupado_em(ctx.elias, ensaio)

      assert Swaps.person_busy_event(ctx.elias, ensaio.starts_at,
               except_event_id: ensaio.id,
               releasing: {ctx.escala_a.id, ctx.elias_a.id}
             ) == nil
    end

    test "o primeiro por data e id desempata, e a agenda sai de duas consultas" do
      ctx = troca_aceita(:cover)
      primeiro = evento_perto_de(ctx.culto_a, -120, :minute)
      event_band_fixture(%{event: primeiro, band: ctx.banda_b})

      encontrado =
        assert_queries(2, fn ->
          Swaps.person_busy_event(ctx.rafael, ctx.culto_a.starts_at, except_event_id: 0)
        end)

      assert encontrado.id == primeiro.id
    end
  end

  describe "swap_mode_available/1" do
    test "é viável quando quem pediu está livre no dia do alvo" do
      %{pedido: pedido} = pedido_feito()

      assert Swaps.swap_mode_available(pedido) == :ok
    end

    test "não é quando o dia do alvo foi cancelado, nem quando já passou" do
      ctx = cenario()
      {:ok, _} = Schedule.cancel_event(ctx.culto_b)

      assert Swaps.swap_mode_available(pedido_de(ctx)) == {:unavailable, :target_closed}

      outro = cenario()
      backdate(outro.culto_b, in_days(-1))

      assert Swaps.swap_mode_available(pedido_de(outro)) == {:unavailable, :target_closed}
    end

    test "não é quando quem pediu já está escalado no dia do alvo" do
      ctx = cenario()
      event_band_fixture(%{event: ctx.culto_b, band: ctx.banda_a})

      assert Swaps.swap_mode_available(pedido_de(ctx)) == {:unavailable, :already_scheduled}
    end

    test "não é quando a vaga do alvo já foi trocada" do
      ctx = cenario()
      gabriela_c = band_member_fixture(%{instrument: "Guitarra"})
      culto_c = event_fixture(%{starts_at: in_days(6)})
      escala_c = event_band_fixture(%{event: culto_c, band: Bands.get_band(gabriela_c.band_id)})

      swap_request_fixture(%{
        requester_event_band: escala_c,
        requester_member: gabriela_c,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b,
        status: :accepted,
        mode: :swap
      })

      assert Swaps.swap_mode_available(pedido_de(ctx)) == {:unavailable, :slot_taken}
    end

    test "não é quando quem pediu ficaria com dois compromissos perto demais" do
      ctx = cenario()
      outra = banda_chamada("Banda C")
      band_member_fixture(%{band: outra, user: ctx.elias, instrument: "Guitarra"})
      ensaio = evento_perto_de(ctx.culto_b, -60, :minute)
      event_band_fixture(%{event: ensaio, band: outra})

      assert {:unavailable, {:conflict, outro}} = Swaps.swap_mode_available(pedido_de(ctx))
      assert outro.id == ensaio.id
    end
  end

  describe "list_accepted_for_event/1 e apply_to_rosters/2" do
    test "o elenco sem troca nenhuma atravessa com substitute nil" do
      %{culto_a: culto_a, banda_a: banda_a, elias: elias} = cenario()

      assert %{substitute: nil} = entrada_do_elenco(culto_a, banda_a, elias)
    end

    test "o líder sem vínculo atravessa: vaga que não existe não se troca" do
      %{culto_a: culto_a, banda_a: banda_a} = troca_aceita(:cover)

      assert %{member: nil, substitute: nil} =
               entrada_do_elenco(culto_a, banda_a, Bands.get_band(banda_a.id).leader_id)
    end

    test "as duas pontas da troca aparecem, cada uma no seu evento" do
      ctx = troca_aceita(:swap)

      assert %{substitute: na_origem} = entrada_do_elenco(ctx.culto_a, ctx.banda_a, ctx.elias)
      assert na_origem.id == ctx.rafael.id

      assert %{substitute: no_destino} = entrada_do_elenco(ctx.culto_b, ctx.banda_b, ctx.rafael)
      assert no_destino.id == ctx.elias.id
    end

    test "em só cobrir, o evento do alvo não é alcançado" do
      ctx = troca_aceita(:cover)

      assert Swaps.list_accepted_for_event(ctx.culto_b) == []
    end

    test "duas vagas trocadas na mesma banda: a marcação é por vaga" do
      ctx = cenario()
      joana = member_fixture(%{name: "Joana Baixista"})
      joana_a = band_member_fixture(%{band: ctx.banda_a, user: joana, instrument: "Baixo"})

      pedro = member_fixture(%{name: "Pedro Baixista"})
      pedro_b = band_member_fixture(%{band: ctx.banda_b, user: pedro, instrument: "Baixo"})

      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b,
        status: :accepted,
        mode: :cover
      })

      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: joana_a,
        target_event_band: ctx.escala_b,
        target_member: pedro_b,
        status: :accepted,
        mode: :cover
      })

      assert %{substitute: %{id: guitarra}} =
               entrada_do_elenco(ctx.culto_a, ctx.banda_a, ctx.elias)

      assert guitarra == ctx.rafael.id

      assert %{substitute: %{id: baixo}} = entrada_do_elenco(ctx.culto_a, ctx.banda_a, joana)
      assert baixo == pedro.id
    end

    test "a ordem do elenco continua sendo a da vaga" do
      ctx = troca_aceita(:cover)

      antes = Enum.map(elenco(ctx.culto_a, ctx.banda_a), & &1.user.id)

      depois =
        [ctx.banda_a.id]
        |> Bands.list_rosters()
        |> Map.get(ctx.banda_a.id)
        |> Enum.map(& &1.user.id)

      assert antes == depois
    end

    test "sai de uma consulta só" do
      ctx = troca_aceita(:swap)

      assert [_] = assert_queries(1, fn -> Swaps.list_accepted_for_event(ctx.culto_a) end)
    end
  end

  describe "a troca aceita se desfaz com a escala" do
    test "desescalar a banda de origem apaga a troca, e o outro elenco volta ao normal" do
      ctx = troca_aceita(:swap)

      {:ok, _} = Schedule.unschedule_band(ctx.escala_a)

      assert Swaps.get_request(ctx.pedido.id) == nil
      assert %{substitute: nil} = entrada_do_elenco(ctx.culto_b, ctx.banda_b, ctx.rafael)
    end

    test "tirar o alvo da banda apaga a troca" do
      ctx = troca_aceita(:cover)

      {:ok, _} = Bands.remove_member(ctx.rafael_b)

      assert Swaps.get_request(ctx.pedido.id) == nil
      assert %{substitute: nil} = entrada_do_elenco(ctx.culto_a, ctx.banda_a, ctx.elias)
    end

    test "o evento cancelado continua mostrando a troca aceita" do
      ctx = troca_aceita(:cover)

      {:ok, _} = Schedule.cancel_event(ctx.culto_a)

      assert %{substitute: substituto} = entrada_do_elenco(ctx.culto_a, ctx.banda_a, ctx.elias)
      assert substituto.id == ctx.rafael.id
    end
  end

  describe "a vaga trocada sai das origens elegíveis" do
    test "quem já cedeu o dia não o oferece de novo" do
      ctx = troca_aceita(:cover)

      assert Swaps.list_origin_options(ctx.elias, ctx.rafael_b) == []
      refute Swaps.can_request?(ctx.elias, ctx.culto_b, ctx.rafael_b)
    end

    test "quem entregou o dia numa troca também não o oferece" do
      ctx = troca_aceita(:swap)

      outro = band_member_fixture(%{instrument: "Guitarra"})
      outro_culto = event_fixture(%{starts_at: in_days(5)})
      event_band_fixture(%{event: outro_culto, band: Bands.get_band(outro.band_id)})

      assert Swaps.list_origin_options(ctx.rafael, outro) == []
    end

    test "em só cobrir, o dia do alvo continua podendo virar origem" do
      ctx = troca_aceita(:cover)

      outro = band_member_fixture(%{instrument: "Guitarra"})
      outro_culto = event_fixture(%{starts_at: in_days(5)})
      event_band_fixture(%{event: outro_culto, band: Bands.get_band(outro.band_id)})

      assert [origem] = Swaps.list_origin_options(ctx.rafael, outro)
      assert origem.event.id == ctx.culto_b.id
    end
  end

  describe "list_accepted_for_user/1" do
    test "traz a troca aceita dos dois lados" do
      ctx = troca_aceita(:cover)

      assert [%SwapRequest{id: pedido}] = Swaps.list_accepted_for_user(ctx.elias)
      assert pedido == ctx.pedido.id

      assert [%SwapRequest{id: mesmo}] = Swaps.list_accepted_for_user(ctx.rafael)
      assert mesmo == ctx.pedido.id
    end

    test "quem não é de nenhuma das duas pontas não vê nada" do
      troca_aceita(:cover)

      assert Swaps.list_accepted_for_user(member_fixture()) == []
    end

    test "o pedido pendente fica de fora: ninguém mudou de dia ainda" do
      ctx = cenario()
      pedido_de(ctx)

      assert Swaps.list_accepted_for_user(ctx.elias) == []
    end

    test "o recusado e o cancelado ficam de fora" do
      ctx = cenario()

      for status <- [:declined, :cancelled] do
        swap_request_fixture(%{
          requester_event_band: ctx.escala_a,
          requester_member: ctx.elias_a,
          target_event_band: ctx.escala_b,
          target_member: ctx.rafael_b,
          status: status
        })
      end

      assert Swaps.list_accepted_for_user(ctx.elias) == []
    end

    test "vem com as duas escalas, os dois eventos e as duas pessoas, de uma consulta só" do
      ctx = troca_aceita(:swap)

      assert [pedido] = assert_queries(1, fn -> Swaps.list_accepted_for_user(ctx.elias) end)

      assert pedido.requester_event_band.event.id == ctx.culto_a.id
      assert pedido.target_event_band.event.id == ctx.culto_b.id
      assert pedido.requester_member.user.name == "Elias Guitarrista"
      assert pedido.target_member.user.name == "Rafael Guitarrista"
    end
  end

  describe "assumed_event_ids/2" do
    test "em só cobrir, quem atendeu assume o dia de quem pediu" do
      ctx = troca_aceita(:cover)
      aceitas = Swaps.list_accepted_for_user(ctx.rafael)

      assert Swaps.assumed_event_ids(aceitas, ctx.rafael) == [ctx.culto_a.id]
    end

    test "em só cobrir, quem pediu não assume dia nenhum" do
      ctx = troca_aceita(:cover)
      aceitas = Swaps.list_accepted_for_user(ctx.elias)

      assert Swaps.assumed_event_ids(aceitas, ctx.elias) == []
    end

    test "em trocar o dia, cada um assume o dia do outro" do
      ctx = troca_aceita(:swap)

      aceitas_do_rafael = Swaps.list_accepted_for_user(ctx.rafael)
      assert Swaps.assumed_event_ids(aceitas_do_rafael, ctx.rafael) == [ctx.culto_a.id]

      aceitas_do_elias = Swaps.list_accepted_for_user(ctx.elias)
      assert Swaps.assumed_event_ids(aceitas_do_elias, ctx.elias) == [ctx.culto_b.id]
    end

    test "sem troca nenhuma, a lista é vazia" do
      assert Swaps.assumed_event_ids([], member_fixture()) == []
    end

    # A conta é sobre a lista que já está na mão: é o que faz o bloco da home
    # custar duas consultas com uma troca ou com dez.
    test "não consulta nada" do
      ctx = troca_aceita(:swap)
      aceitas = Swaps.list_accepted_for_user(ctx.rafael)

      assert assert_queries(0, fn -> Swaps.assumed_event_ids(aceitas, ctx.rafael) end) ==
               [ctx.culto_a.id]
    end
  end

  describe "annotate_upcoming/3" do
    test "o evento sem troca nenhuma fica com swap nil" do
      ctx = cenario()

      assert [%{swap: nil}] =
               Swaps.annotate_upcoming([ctx.culto_a], ctx.elias, [])
    end

    test "o dia assumido vem marcado com o titular da vaga" do
      ctx = troca_aceita(:cover)
      aceitas = Swaps.list_accepted_for_user(ctx.rafael)

      assert [%{swap: {:assumed, titular}}] =
               Swaps.annotate_upcoming([ctx.culto_a], ctx.rafael, aceitas)

      assert titular.id == ctx.elias.id
    end

    test "o dia cedido vem marcado com quem vai no lugar" do
      ctx = troca_aceita(:cover)
      aceitas = Swaps.list_accepted_for_user(ctx.elias)

      assert [%{swap: {:released, substituto}}] =
               Swaps.annotate_upcoming([ctx.culto_a], ctx.elias, aceitas)

      assert substituto.id == ctx.rafael.id
    end

    test "em só cobrir, o dia do alvo não ganha marca nenhuma" do
      ctx = troca_aceita(:cover)

      for {user, quem} <- [{ctx.rafael, "quem cobriu"}, {ctx.elias, "quem foi coberto"}] do
        aceitas = Swaps.list_accepted_for_user(user)

        assert [%{swap: nil}] = Swaps.annotate_upcoming([ctx.culto_b], user, aceitas),
               "o dia do alvo não muda de dono para #{quem}"
      end
    end

    test "em trocar o dia, cada um vê as duas linhas marcadas" do
      ctx = troca_aceita(:swap)
      eventos = [ctx.culto_a, ctx.culto_b]

      aceitas_do_rafael = Swaps.list_accepted_for_user(ctx.rafael)

      assert [%{swap: {:assumed, _}}, %{swap: {:released, _}}] =
               Swaps.annotate_upcoming(eventos, ctx.rafael, aceitas_do_rafael)

      aceitas_do_elias = Swaps.list_accepted_for_user(ctx.elias)

      assert [%{swap: {:released, _}}, %{swap: {:assumed, _}}] =
               Swaps.annotate_upcoming(eventos, ctx.elias, aceitas_do_elias)
    end

    test "a troca de terceiros não marca a agenda de quem olha" do
      ctx = troca_aceita(:swap)
      pastor = pastor_fixture()

      aceitas = Swaps.list_accepted_for_user(pastor)

      assert [%{swap: nil}, %{swap: nil}] =
               Swaps.annotate_upcoming([ctx.culto_a, ctx.culto_b], pastor, aceitas)
    end

    test "a ordem dos eventos é a que chegou" do
      ctx = troca_aceita(:swap)
      aceitas = Swaps.list_accepted_for_user(ctx.rafael)

      eventos = Swaps.annotate_upcoming([ctx.culto_b, ctx.culto_a], ctx.rafael, aceitas)

      assert Enum.map(eventos, & &1.id) == [ctx.culto_b.id, ctx.culto_a.id]
    end

    test "não consulta nada, com quantos eventos forem" do
      ctx = troca_aceita(:swap)
      aceitas = Swaps.list_accepted_for_user(ctx.rafael)

      assert_queries(0, fn ->
        Swaps.annotate_upcoming([ctx.culto_a, ctx.culto_b], ctx.rafael, aceitas)
      end)
    end
  end

  # O elenco de uma banda naquele evento, já com as vagas trocadas marcadas —
  # é o que a tela do evento monta, escrito uma vez para os testes não
  # repetirem as duas chamadas.
  # As notificações dentro da plataforma (US 4.5). O sentido é o mesmo dos
  # e-mails — avisa quem **não** agiu —, e o que se prova aqui é que os dois
  # canais saem do mesmo ponto: um fato que avisasse por um só é exatamente o
  # defeito que ninguém percebe.
  describe "a notificação de cada fato da troca (US 4.5)" do
    test "pedir troca notifica o alvo, e não quem pediu" do
      ctx = cenario()

      assert {:ok, _pedido} =
               Swaps.request_swap(ctx.elias, ctx.culto_b, ctx.rafael_b, ctx.escala_a.id)

      assert [notificacao] = Notifications.list_for_user(ctx.rafael)
      assert notificacao.kind == :swap_requested
      assert notificacao.title == "Pedido de troca de escala"
      assert notificacao.path == "/swaps?from=notification"
      assert is_nil(notificacao.read_at)

      assert Notifications.list_for_user(ctx.elias) == []
    end

    test "o texto do pedido diz quem pediu e os dois dias em questão" do
      ctx = cenario()

      {:ok, _pedido} = Swaps.request_swap(ctx.elias, ctx.culto_b, ctx.rafael_b, ctx.escala_a.id)

      assert [%{body: texto}] = Notifications.list_for_user(ctx.rafael)
      assert texto =~ "Elias Guitarrista"
      assert texto =~ ctx.culto_a.title
      assert texto =~ ctx.culto_b.title
    end

    # O alvo foi chamado para agir e o pedido some da lista dele: sumir em
    # silêncio o faria procurar o que não está mais lá.
    test "cancelar notifica o alvo, e não quem cancelou" do
      ctx = pedido_feito()

      assert {:ok, _cancelado} = Swaps.cancel_request(ctx.elias, ctx.pedido)

      assert [notificacao] = Notifications.list_for_user(ctx.rafael)
      assert notificacao.kind == :swap_cancelled
      assert notificacao.title == "Pedido de troca cancelado"
      assert notificacao.body =~ "Elias Guitarrista"
      assert notificacao.body =~ ctx.culto_b.title

      assert Notifications.list_for_user(ctx.elias) == []
    end

    test "aceitar em só cobrir notifica quem pediu, e o texto diz o modo" do
      ctx = pedido_feito()

      assert {:ok, _aceito} = Swaps.accept_request(ctx.rafael, ctx.pedido, "cover")

      assert [notificacao] = Notifications.list_for_user(ctx.elias)
      assert notificacao.kind == :swap_accepted
      assert notificacao.title == "Pedido de troca aceito"
      assert notificacao.body =~ "Rafael Guitarrista vai cobrir você"
      assert notificacao.body =~ ctx.culto_a.title
      assert notificacao.body =~ "O dia dele(a) não muda."

      assert Notifications.list_for_user(ctx.rafael) == []
    end

    # A segunda metade é o que diferencia os dois modos, e omiti-la faria a
    # pessoa faltar num dia que passou a ser dela.
    test "aceitar em trocar o dia diz também qual dia quem pediu assumiu" do
      ctx = pedido_feito()

      assert {:ok, _aceito} = Swaps.accept_request(ctx.rafael, ctx.pedido, "swap")

      assert [notificacao] = Notifications.list_for_user(ctx.elias)
      assert notificacao.kind == :swap_accepted
      assert notificacao.body =~ "você está liberado de"
      assert notificacao.body =~ ctx.culto_a.title
      assert notificacao.body =~ "e passou a tocar em"
      assert notificacao.body =~ ctx.culto_b.title
    end

    test "recusar notifica quem pediu, e o dia continua sendo dele" do
      ctx = pedido_feito()

      assert {:ok, _recusado} = Swaps.decline_request(ctx.rafael, ctx.pedido)

      assert [notificacao] = Notifications.list_for_user(ctx.elias)
      assert notificacao.kind == :swap_declined
      assert notificacao.title == "Pedido de troca recusado"
      assert notificacao.body =~ "Rafael Guitarrista recusou"
      assert notificacao.body =~ ctx.culto_a.title

      assert Notifications.list_for_user(ctx.rafael) == []
    end

    # Notificar é anunciar, e não se anuncia o que não aconteceu: quando a
    # gravação é recusada, ninguém é avisado de nada.
    test "pedido recusado pela elegibilidade não faz notificação nenhuma nascer" do
      ctx = cenario()

      assert {:error, :ineligible} =
               Swaps.request_swap(ctx.rafael, ctx.culto_b, ctx.rafael_b, ctx.escala_a.id)

      assert Notifications.list_for_user(ctx.rafael) == []
      assert Notifications.list_for_user(ctx.elias) == []
    end

    test "aceite recusado dentro da transação não faz notificação nenhuma nascer" do
      ctx = troca_aceita(:swap)

      outro = pedido_de(ctx)

      assert {:error, :slot_taken} = Swaps.accept_request(ctx.rafael, outro, "cover")
      assert Notifications.list_for_user(ctx.elias) == []
    end

    # O caminho leva à caixa de entrada **e** se identifica: é o
    # `?from=notification` que faz `/swaps` reconhecer quem chegou por um aviso
    # e poder dizer que o pedido não está mais lá.
    test "a notificação da troca leva sempre à caixa de entrada dela, dizendo de onde veio" do
      ctx = pedido_feito()

      {:ok, _} = Swaps.decline_request(ctx.rafael, ctx.pedido)

      assert [%{path: "/swaps?from=notification"}] = Notifications.list_for_user(ctx.elias)
    end
  end

  defp elenco(event, band) do
    [band.id]
    |> Bands.list_rosters()
    |> Swaps.apply_to_rosters(Swaps.list_accepted_for_event(event))
    |> Map.get(band.id)
  end

  defp entrada_do_elenco(event, band, %{id: user_id}),
    do: entrada_do_elenco(event, band, user_id)

  defp entrada_do_elenco(event, band, user_id) when is_integer(user_id),
    do: event |> elenco(band) |> Enum.find(&(&1.user.id == user_id))

  # `person_busy_event/3` na forma que quase todo teste usa: a pessoa, o evento
  # que está sendo montado, e nada sendo cedido.
  defp ocupado_em(user, event),
    do: Swaps.person_busy_event(user, event.starts_at, except_event_id: event.id)

  defp evento_perto_de(event, quanto, unidade),
    do: event_fixture(%{starts_at: DateTime.add(event.starts_at, quanto, unidade)})

  defp pedido_de(ctx) do
    pedido =
      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b
      })

    Swaps.get_request(pedido.id)
  end

  # O cenário com a troca **já aceita**, gravada direto no repositório: é o
  # único jeito de montar <q>esta vaga já está trocada</q> sem passar pela
  # regra que o teste quer ver sendo aplicada.
  defp troca_aceita(mode) do
    ctx = cenario()

    pedido =
      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b,
        status: :accepted,
        mode: mode
      })

    Map.put(ctx, :pedido, Swaps.get_request(pedido.id))
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
