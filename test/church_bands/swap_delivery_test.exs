defmodule ChurchBands.SwapDeliveryTest do
  @moduledoc """
  O que acontece quando o servidor de e-mail está fora do ar.

  Pedir troca — e responder a um pedido — é gravar um registro **e** avisar
  alguém; se só a primeira metade acontece, quem espera notícia não a recebe:
  o alvo não sabe que foi chamado, ou quem pediu não sabe que já tem resposta.
  Por isso a falha é dita em vez de engolida, como no convite (US 1.1).

  **Desde a US 4.5 há um segundo canal**, e é ele que salva a pessoa aqui: a
  notificação dentro da plataforma sai **antes** do e-mail, e por isso ela
  nasce mesmo com o servidor de e-mail fora do ar. Invertida a ordem, uma caixa
  de saída caída deixaria quem espera sem aviso nenhum — e a central existe
  justamente para isso não acontecer.

  **O pedido fica gravado**: o que falhou foi o aviso, e apagá-lo esconderia da
  pessoa o que ela acabou de fazer. É o mesmo efeito do convite.

  O caso é **síncrono** de propósito: a configuração do mailer é global e uma
  troca dessas valeria também para os testes rodando em paralelo.
  """
  use ChurchBandsWeb.ConnCase, async: false

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Notifications
  alias ChurchBands.Swaps

  setup do
    original = Application.get_env(:church_bands, ChurchBands.Mailer)

    Application.put_env(:church_bands, ChurchBands.Mailer,
      adapter: ChurchBands.FailingMailerAdapter
    )

    on_exit(fn -> Application.put_env(:church_bands, ChurchBands.Mailer, original) end)

    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = band_fixture(%{name: "Banda A #{System.unique_integer([:positive])}"})
    banda_b = band_fixture(%{name: "Banda B #{System.unique_integer([:positive])}"})

    culto_noite = event_fixture(%{title: "Culto da Noite", starts_at: in_days(3)})
    culto_manha = event_fixture(%{title: "Culto da Manhã", starts_at: in_days(4)})

    %{
      elias: elias,
      rafael: rafael,
      culto_manha: culto_manha,
      elias_a: band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"}),
      rafael_b: band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"}),
      escala_a: event_band_fixture(%{event: culto_noite, band: banda_a}),
      escala_b: event_band_fixture(%{event: culto_manha, band: banda_b})
    }
  end

  describe "Swaps.request_swap/4" do
    test "avisa que a entrega falhou em vez de dar o pedido por enviado", ctx do
      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Swaps.request_swap(ctx.elias, ctx.culto_manha, ctx.rafael_b, ctx.escala_a.id)
    end

    test "o pedido continua gravado: o que falhou foi o aviso", ctx do
      Swaps.request_swap(ctx.elias, ctx.culto_manha, ctx.rafael_b, ctx.escala_a.id)

      assert [pedido] = Swaps.list_sent(ctx.elias)
      assert pedido.status == :pending
    end
  end

  # O ponto de o segundo canal existir: o e-mail caiu, e a pessoa ainda assim
  # descobre pelo sino que foi chamada.
  describe "a notificação dentro da plataforma sobrevive à queda do e-mail" do
    test "o alvo é notificado mesmo com a entrega falhando", ctx do
      Swaps.request_swap(ctx.elias, ctx.culto_manha, ctx.rafael_b, ctx.escala_a.id)

      assert [%{kind: :swap_requested}] = Notifications.list_for_user(ctx.rafael)
      assert Notifications.unread_count(ctx.rafael) == 1
    end

    test "quem pediu é notificado da resposta mesmo com a entrega falhando", ctx do
      pedido = pedido_pendente(ctx)

      Swaps.decline_request(ctx.rafael, pedido)

      assert [%{kind: :swap_declined}] = Notifications.list_for_user(ctx.elias)
    end
  end

  describe "Swaps.cancel_request/2" do
    test "avisa que a entrega falhou, com o pedido já cancelado", ctx do
      pedido = pedido_pendente(ctx)

      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Swaps.cancel_request(ctx.elias, pedido)

      assert Swaps.get_request(pedido.id).status == :cancelled
    end
  end

  describe "Swaps.accept_request/3 e decline_request/2" do
    test "o aceite fica gravado, e a entrega que falhou é dita", ctx do
      pedido = pedido_pendente(ctx)

      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Swaps.accept_request(ctx.rafael, pedido, "cover")

      assert %{status: :accepted, mode: :cover} = Swaps.get_request(pedido.id)
    end

    test "a recusa também", ctx do
      pedido = pedido_pendente(ctx)

      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Swaps.decline_request(ctx.rafael, pedido)

      assert Swaps.get_request(pedido.id).status == :declined
    end
  end

  describe "as telas" do
    test "a de pedido diz que o e-mail não saiu, e leva para a lista mesmo assim", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)

      {:ok, view, _html} =
        live(conn, ~p"/events/#{ctx.culto_manha.id}/members/#{ctx.rafael_b.id}/swap")

      assert {:ok, _lista, html} =
               view
               |> form("#swap-request-form",
                 swap_request: %{origin_event_band_id: ctx.escala_a.id}
               )
               |> render_submit()
               |> follow_redirect(conn, "/swaps")

      assert html =~
               "Pedido de troca criado, mas não foi possível enviar o e-mail para Rafael Guitarrista."

      assert [_pedido] = Swaps.list_sent(ctx.elias)
    end

    test "a de trocas diz que o cancelamento não foi avisado", ctx do
      pedido = pedido_pendente(ctx)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.elias) |> live(~p"/swaps")

      html = view |> element("#cancel-request-#{pedido.id}") |> render_click()

      assert html =~ "Pedido de troca cancelado, mas não foi possível avisar por e-mail."
      assert Swaps.get_request(pedido.id).status == :cancelled
    end

    test "a de trocas diz que a resposta não foi avisada, com o aceite já gravado", ctx do
      pedido = pedido_pendente(ctx)

      {:ok, view, _html} = ctx.conn |> log_in_user(ctx.rafael) |> live(~p"/swaps")

      html = view |> element("#accept-cover-#{pedido.id}") |> render_click()

      assert html =~ "Resposta registrada, mas não foi possível avisar por e-mail."
      assert Swaps.get_request(pedido.id).status == :accepted
    end
  end

  # O pedido é montado pelo fixture, que vai direto ao repositório: só a ação
  # sob teste é que roda com o servidor de e-mail fora do ar.
  defp pedido_pendente(ctx) do
    pedido =
      swap_request_fixture(%{
        requester_event_band: ctx.escala_a,
        requester_member: ctx.elias_a,
        target_event_band: ctx.escala_b,
        target_member: ctx.rafael_b
      })

    Swaps.get_request(pedido.id)
  end
end
