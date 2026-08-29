defmodule ChurchBandsWeb.SwapLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias ChurchBands.Schedule
  alias ChurchBands.Swaps

  defp banda_chamada(nome, attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # O Elias pediu troca ao Rafael: ele não pode no "Culto da Noite" e o dia do
  # Rafael em jogo é o "Culto da Manhã".
  defp cenario(_contexto) do
    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = banda_chamada("Banda A")
    banda_b = banda_chamada("Banda B")

    culto_noite = event_fixture(%{title: "Culto da Noite", starts_at: in_days(3)})
    culto_manha = event_fixture(%{title: "Culto da Manhã", starts_at: in_days(4)})

    escala_a = event_band_fixture(%{event: culto_noite, band: banda_a})
    escala_b = event_band_fixture(%{event: culto_manha, band: banda_b})

    elias_a = band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"})
    rafael_b = band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"})

    pedido =
      swap_request_fixture(%{
        requester_event_band: escala_a,
        requester_member: elias_a,
        target_event_band: escala_b,
        target_member: rafael_b
      })

    %{
      elias: elias,
      rafael: rafael,
      banda_a: banda_a,
      banda_b: banda_b,
      culto_noite: culto_noite,
      culto_manha: culto_manha,
      escala_a: escala_a,
      escala_b: escala_b,
      elias_a: elias_a,
      rafael_b: rafael_b,
      pedido: pedido
    }
  end

  # O aviso da US 4.5 sobrevive ao pedido que o gerou — ele não guarda qual foi
  # —, então clicar num aviso antigo pode terminar numa tela sem nada. A linha
  # que explica isso é a única coisa que se pode dizer sem devolver ao aviso um
  # `swap_request_id` que a tabela recusa de propósito.
  describe "quem chega por uma notificação" do
    setup [:cenario]

    test "com as duas listas vazias, a tela diz que o pedido não está mais aqui", ctx do
      conn = log_in_user(ctx.conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/swaps?from=notification")

      assert has_element?(view, "#swaps-from-notification-empty")
      assert render(view) =~ "não está mais nesta lista"
    end

    test "com um pedido na tela, a linha não aparece: a lista já conta a verdade", ctx do
      {:ok, view, _html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps?from=notification")

      refute has_element?(view, "#swaps-from-notification-empty")
    end

    test "quem chega pelo menu, com tudo vazio, não recebe explicação nenhuma", ctx do
      conn = log_in_user(ctx.conn, member_fixture())

      {:ok, view, _html} = live(conn, ~p"/swaps")

      assert has_element?(view, "#sent-requests-empty")
      refute has_element?(view, "#swaps-from-notification-empty")
    end
  end

  describe "as duas listas" do
    setup [:cenario]

    test "quem pediu vê o pedido em Pedidos que enviei, com os dois dias e a função", ctx do
      {:ok, view, html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert has_element?(view, "#sent-request-#{ctx.pedido.id}")
      assert has_element?(view, "#received-requests-empty")
      assert html =~ "Rafael Guitarrista"
      assert html =~ "Guitarra"
      assert html =~ "Culto da Noite"
      assert html =~ "Culto da Manhã"
      assert html =~ ctx.banda_a.name
      assert html =~ ctx.banda_b.name
      assert view |> element("#sent-status-#{ctx.pedido.id}") |> render() =~ "Pendente"
    end

    test "quem recebeu vê o mesmo pedido em Pedidos que recebi, e não o cancela", ctx do
      {:ok, view, html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert has_element?(view, "#received-request-#{ctx.pedido.id}")
      assert has_element?(view, "#sent-requests-empty")
      assert html =~ "Elias Guitarrista"
      refute has_element?(view, "#cancel-request-#{ctx.pedido.id}")
    end

    test "quem não pediu nem recebeu nada vê os dois estados vazios", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(member_fixture()) |> live(~p"/swaps")

      assert has_element?(view, "#sent-requests-empty")
      assert has_element?(view, "#received-requests-empty")
    end

    test "o Pastor vê só os pedidos dele: acesso total não abre a caixa dos outros", ctx do
      {:ok, view, html} = ctx.conn |> log_in_user(pastor_fixture()) |> live(~p"/swaps")

      assert has_element?(view, "#sent-requests-empty")
      assert has_element?(view, "#received-requests-empty")
      refute html =~ "Elias Guitarrista"
    end

    test "o evento cancelado aparece riscado, e o pedido continua pendente", ctx do
      {:ok, _} = Schedule.cancel_event(ctx.culto_noite)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert view |> element("#sent-origin-#{ctx.pedido.id} span.line-through") |> render() =~
               "Culto da Noite"

      assert view |> element("#sent-status-#{ctx.pedido.id}") |> render() =~ "Pendente"
    end

    test "visitante é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/swaps")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "cancelar" do
    setup [:cenario]

    test "o solicitante cancela, o estado vira Cancelado e o alvo é avisado", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      html = view |> element("#cancel-request-#{ctx.pedido.id}") |> render_click()

      assert html =~ "Pedido de troca cancelado."
      assert view |> element("#sent-status-#{ctx.pedido.id}") |> render() =~ "Cancelado"
      refute has_element?(view, "#cancel-request-#{ctx.pedido.id}")
      assert Swaps.get_request(ctx.pedido.id).status == :cancelled

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.rafael.email
        assert email.subject == "Pedido de troca cancelado"
      end)
    end

    test "a confirmação nomeia o alvo", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert view |> element("#cancel-request-#{ctx.pedido.id}") |> render() =~
               "Cancelar o pedido de troca com Rafael Guitarrista?"
    end

    test "o alvo forçando o cancelamento não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      html = render_click(view, "cancel", %{"id" => to_string(ctx.pedido.id)})

      assert html =~ "Não foi possível cancelar este pedido."
      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "cancelar de novo o que já está cancelado não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      view |> element("#cancel-request-#{ctx.pedido.id}") |> render_click()

      html = render_click(view, "cancel", %{"id" => to_string(ctx.pedido.id)})

      assert html =~ "Não foi possível cancelar este pedido."
      assert Swaps.get_request(ctx.pedido.id).status == :cancelled
    end

    test "id inventado não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert render_click(view, "cancel", %{"id" => "banana"}) =~
               "Não foi possível cancelar este pedido."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end
  end

  describe "responder" do
    setup [:cenario]

    test "o alvo vê os três botões, e quem pediu não vê nenhum", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert has_element?(view, "#accept-cover-#{ctx.pedido.id}", "Só cobrir")
      assert has_element?(view, "#accept-swap-#{ctx.pedido.id}", "Trocar o dia")
      assert has_element?(view, "#decline-#{ctx.pedido.id}", "Recusar")
      refute has_element?(view, "#swap-unavailable-#{ctx.pedido.id}")

      {:ok, elias_view, _} = build_conn() |> log_in_user(ctx.elias) |> live(~p"/swaps")

      refute has_element?(elias_view, "#accept-cover-#{ctx.pedido.id}")
      refute has_element?(elias_view, "#decline-#{ctx.pedido.id}")
    end

    test "as confirmações dizem o que cada botão faz", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#accept-cover-#{ctx.pedido.id}") |> render() =~
               "Cobrir Elias Guitarrista em Culto da Noite? O seu dia continua sendo seu."

      assert view |> element("#accept-swap-#{ctx.pedido.id}") |> render() =~
               "Você passa a tocar em Culto da Noite e ele(a) em Culto da Manhã."

      assert view |> element("#decline-#{ctx.pedido.id}") |> render() =~
               "Recusar o pedido de troca de Elias Guitarrista?"
    end

    test "só cobrir grava o aceite, avisa quem pediu e tira os botões", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      html = view |> element("#accept-cover-#{ctx.pedido.id}") |> render_click()

      assert html =~ "Você vai cobrir Elias Guitarrista em Culto da Noite."

      assert view |> element("#received-status-#{ctx.pedido.id}") |> render() =~ "Aceito — cobrir"
      refute has_element?(view, "#accept-cover-#{ctx.pedido.id}")

      assert %{status: :accepted, mode: :cover} = Swaps.get_request(ctx.pedido.id)

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.elias.email
        assert email.subject == "Pedido de troca aceito"
      end)
    end

    test "trocar o dia grava o aceite e a mensagem nomeia os dois eventos", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      html = view |> element("#accept-swap-#{ctx.pedido.id}") |> render_click()

      assert html =~
               "Troca feita com Elias Guitarrista: você toca em Culto da Noite e ele(a) em Culto da Manhã."

      assert view |> element("#received-status-#{ctx.pedido.id}") |> render() =~ "Aceito — troca"
      assert %{status: :accepted, mode: :swap} = Swaps.get_request(ctx.pedido.id)
    end

    test "recusar encerra o pedido sem mudar escala nenhuma, e quem pediu vê o estado", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#decline-#{ctx.pedido.id}") |> render_click() =~
               "Pedido de troca recusado."

      assert Swaps.get_request(ctx.pedido.id).status == :declined

      assert_email_sent(fn email -> assert email.subject == "Pedido de troca recusado" end)

      {:ok, elias_view, _} = build_conn() |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert elias_view |> element("#sent-status-#{ctx.pedido.id}") |> render() =~ "Recusado"
    end

    test "o dia do alvo cancelado tira só o trocar: cobrir e recusar continuam", ctx do
      {:ok, _} = Schedule.cancel_event(ctx.culto_manha)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      refute has_element?(view, "#accept-swap-#{ctx.pedido.id}")
      assert has_element?(view, "#accept-cover-#{ctx.pedido.id}")
      assert has_element?(view, "#decline-#{ctx.pedido.id}")

      assert view |> element("#swap-unavailable-#{ctx.pedido.id}") |> render() =~
               "o seu dia deste pedido foi cancelado ou já passou."

      assert view |> element("#accept-cover-#{ctx.pedido.id}") |> render_click() =~
               "Você vai cobrir Elias Guitarrista em Culto da Noite."
    end

    test "trocar o dia some, com o motivo, quando quem pediu já está no dia do alvo", ctx do
      event_band_fixture(%{event: ctx.culto_manha, band: ctx.banda_a})

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      refute has_element?(view, "#accept-swap-#{ctx.pedido.id}")
      assert has_element?(view, "#accept-cover-#{ctx.pedido.id}")

      assert view |> element("#swap-unavailable-#{ctx.pedido.id}") |> render() =~
               "Trocar o dia não é possível: Elias Guitarrista já está escalado(a) no seu evento."
    end

    test "trocar o dia some quando a vaga do alvo já foi trocada", ctx do
      outro = band_member_fixture(%{instrument: "Guitarra"})
      outro_culto = event_fixture(%{starts_at: in_days(6)})

      swap_request_fixture(%{
        requester_event_band:
          event_band_fixture(%{
            event: outro_culto,
            band: ChurchBands.Bands.get_band(outro.band_id)
          }),
        requester_member: outro,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b,
        status: :accepted,
        mode: :swap
      })

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#swap-unavailable-#{ctx.pedido.id}") |> render() =~
               "a sua vaga neste dia já foi trocada."
    end

    test "trocar o dia some quando quem pediu ficaria com dois compromissos perto demais", ctx do
      outra = banda_chamada("Banda C")
      band_member_fixture(%{band: outra, user: ctx.elias, instrument: "Guitarra"})

      ensaio =
        event_fixture(%{
          title: "Ensaio Geral",
          starts_at: DateTime.add(ctx.culto_manha.starts_at, -60, :minute)
        })

      event_band_fixture(%{event: ensaio, band: outra})

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#swap-unavailable-#{ctx.pedido.id}") |> render() =~
               "Elias Guitarrista já toca em Ensaio Geral, no mesmo horário."
    end

    test "o aceite em cobrir é recusado quando o alvo já toca perto dali", ctx do
      ensaio =
        event_fixture(%{
          title: "Ensaio Geral",
          starts_at: DateTime.add(ctx.culto_noite.starts_at, -90, :minute)
        })

      event_band_fixture(%{event: ensaio, band: ctx.banda_b})

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#accept-cover-#{ctx.pedido.id}") |> render_click() =~
               "Você já toca em Ensaio Geral, no mesmo horário."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "o aceite é recusado quando a vaga de origem já foi trocada", ctx do
      outro_alvo = band_member_fixture(%{band: ctx.banda_b, instrument: "Guitarra"})

      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: outro_alvo,
        status: :accepted,
        mode: :cover
      })

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert view |> element("#accept-cover-#{ctx.pedido.id}") |> render_click() =~
               "Esta vaga já foi trocada."
    end

    test "o solicitante forçando o aceite do próprio pedido não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      assert aceite_forcado(view, ctx.pedido, "cover") =~
               "Este pedido não pode mais ser respondido."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "quem tem acesso total forçando o aceite de terceiros não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(pastor_fixture()) |> live(~p"/swaps")

      assert aceite_forcado(view, ctx.pedido, "swap") =~
               "Este pedido não pode mais ser respondido."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "responder de novo o que já foi respondido não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      view |> element("#decline-#{ctx.pedido.id}") |> render_click()

      assert aceite_forcado(view, ctx.pedido, "cover") =~
               "Este pedido não pode mais ser respondido."

      assert render_click(view, "decline", %{"id" => to_string(ctx.pedido.id)}) =~
               "Este pedido não pode mais ser respondido."

      assert Swaps.get_request(ctx.pedido.id).status == :declined
    end

    test "o evento de origem cancelado tira os botões e recusa a resposta forçada", ctx do
      {:ok, _} = Schedule.cancel_event(ctx.culto_noite)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      refute has_element?(view, "#accept-cover-#{ctx.pedido.id}")
      refute has_element?(view, "#decline-#{ctx.pedido.id}")

      assert aceite_forcado(view, ctx.pedido, "cover") =~
               "Este pedido não pode mais ser respondido."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "o modo forjado não grava nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert aceite_forcado(view, ctx.pedido, "banana") =~
               "Este pedido não pode mais ser respondido."

      assert Swaps.get_request(ctx.pedido.id).status == :pending
    end

    test "id inventado não muda nada", ctx do
      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert render_click(view, "accept", %{"id" => "banana", "mode" => "cover"}) =~
               "Este pedido não pode mais ser respondido."

      assert render_click(view, "decline", %{"id" => "banana"}) =~
               "Este pedido não pode mais ser respondido."
    end
  end

  describe "a vaga que some" do
    setup [:cenario]

    test "desescalar a banda do alvo tira o pedido das duas listas", ctx do
      {:ok, _} = Schedule.unschedule_band(ctx.escala_b)

      {:ok, elias_view, _} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")
      {:ok, rafael_view, _} = build_conn() |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert has_element?(elias_view, "#sent-requests-empty")
      assert has_element?(rafael_view, "#received-requests-empty")
    end

    test "remover o alvo da banda tira o pedido das duas listas", ctx do
      {:ok, _} = ChurchBands.Bands.remove_member(ctx.rafael_b)

      {:ok, elias_view, _} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")
      {:ok, rafael_view, _} = build_conn() |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert has_element?(elias_view, "#sent-requests-empty")
      assert has_element?(rafael_view, "#received-requests-empty")
    end
  end

  describe "tempo real (#112)" do
    setup [:cenario]

    test "a view de quem pediu reage sozinha ao aceite, sem F5", ctx do
      {:ok, elias_view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      refute render(elias_view) =~ "Aceito — cobrir"

      # O aceite acontece por um caminho totalmente separado da `elias_view` —
      # uma segunda conexão, como o resto do arquivo já usa — e ela nunca é
      # re-navegada depois.
      {:ok, rafael_view, _} = build_conn() |> log_in_user(ctx.rafael) |> live(~p"/swaps")
      rafael_view |> element("#accept-cover-#{ctx.pedido.id}") |> render_click()

      assert render(elias_view) =~ "Aceito — cobrir"
    end

    test "a view de quem recebeu reage sozinha ao cancelamento, sem F5", ctx do
      {:ok, rafael_view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      assert has_element?(rafael_view, "#accept-cover-#{ctx.pedido.id}")

      {:ok, _} = Swaps.cancel_request(ctx.elias, Swaps.get_request(ctx.pedido.id))

      refute has_element?(rafael_view, "#accept-cover-#{ctx.pedido.id}")

      assert rafael_view |> element("#received-status-#{ctx.pedido.id}") |> render() =~
               "Cancelado"
    end
  end

  # O evento chega pelo socket, sem botão nenhum: é assim que se testa quem
  # sabe que ele existe e o dispara mesmo sem a tela oferecer.
  defp aceite_forcado(view, pedido, mode),
    do: render_click(view, "accept", %{"id" => to_string(pedido.id), "mode" => mode})
end
