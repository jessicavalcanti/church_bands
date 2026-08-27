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

    test "quem recebeu vê o mesmo pedido em Pedidos que recebi, e só leitura", ctx do
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
end
