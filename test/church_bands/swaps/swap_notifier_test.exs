defmodule ChurchBands.Swaps.SwapNotifierTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import ChurchBands.SwapsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.LocalTime
  alias ChurchBands.Swaps
  alias ChurchBands.Swaps.SwapNotifier

  defp banda_chamada(nome) do
    band_fixture(%{name: "#{nome} #{System.unique_integer([:positive])}"})
  end

  setup do
    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = banda_chamada("Banda A")
    banda_b = banda_chamada("Banda B")

    culto_noite = event_fixture(%{title: "Culto da Noite", starts_at: in_days(3)})
    culto_manha = event_fixture(%{title: "Culto da Manhã", starts_at: in_days(4)})

    pedido =
      swap_request_fixture(%{
        requester_event_band: event_band_fixture(%{event: culto_noite, band: banda_a}),
        requester_member:
          band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"}),
        target_event_band: event_band_fixture(%{event: culto_manha, band: banda_b}),
        target_member: band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"})
      })

    %{
      elias: elias,
      rafael: rafael,
      culto_noite: culto_noite,
      culto_manha: culto_manha,
      pedido: Swaps.get_request(pedido.id)
    }
  end

  describe "deliver_request/1" do
    test "escreve ao alvo dizendo quem pediu, qual função e quais dois dias", ctx do
      assert {:ok, _} = SwapNotifier.deliver_request(ctx.pedido)

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.rafael.email
        assert email.subject == "Pedido de troca de escala"
        assert email.text_body =~ "Elias Guitarrista"
        assert email.text_body =~ "Guitarra"
        assert email.text_body =~ "Culto da Noite"
        assert email.text_body =~ "Culto da Manhã"
        assert email.text_body =~ LocalTime.format(ctx.culto_noite.starts_at, :short)
        assert email.text_body =~ LocalTime.format(ctx.culto_manha.starts_at, :short)
      end)
    end

    test "leva o link de /swaps, e nenhum token: quem recebe tem conta", ctx do
      assert {:ok, _} = SwapNotifier.deliver_request(ctx.pedido)

      assert_email_sent(fn email ->
        # `/swaps/<token>` é o que o convite e a redefinição de senha fazem —
        # aqui não há token porque o destinatário faz login como sempre.
        refute email.text_body =~ ~r{/swaps/\S}
        assert email.text_body =~ "/swaps"
      end)
    end
  end

  describe "deliver_accepted/1" do
    test "em cobrir, diz a quem pediu que ele está liberado daquele dia", ctx do
      assert {:ok, _} = SwapNotifier.deliver_accepted(aceito(ctx.pedido, :cover))

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.elias.email
        assert email.subject == "Pedido de troca aceito"
        assert email.text_body =~ "Rafael Guitarrista aceitou"
        assert email.text_body =~ "Você está liberado de: Culto da Noite"
        # Em cobrir o dia do alvo não muda, e prometer o contrário faria a
        # pessoa aparecer num culto que não é dela.
        refute email.text_body =~ "E passou a tocar em:"
        assert email.text_body =~ "O dia dele(a) não muda."
      end)
    end

    test "em trocar, diz também qual dia ele assumiu", ctx do
      assert {:ok, _} = SwapNotifier.deliver_accepted(aceito(ctx.pedido, :swap))

      assert_email_sent(fn email ->
        assert email.text_body =~ "Você está liberado de: Culto da Noite"
        assert email.text_body =~ "E passou a tocar em: Culto da Manhã"
        assert email.text_body =~ LocalTime.format(ctx.culto_manha.starts_at, :short)
      end)
    end
  end

  describe "deliver_declined/1" do
    test "avisa quem pediu de que o dia continua sendo dele", ctx do
      assert {:ok, _} = SwapNotifier.deliver_declined(ctx.pedido)

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.elias.email
        assert email.subject == "Pedido de troca recusado"
        assert email.text_body =~ "Rafael Guitarrista recusou"
        assert email.text_body =~ "O dia continua sendo seu: Culto da Noite"
        assert email.text_body =~ "/swaps"
      end)
    end
  end

  describe "deliver_cancelled/1" do
    test "avisa o alvo de que o pedido saiu da lista dele", ctx do
      assert {:ok, _} = SwapNotifier.deliver_cancelled(ctx.pedido)

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.rafael.email
        assert email.subject == "Pedido de troca cancelado"
        assert email.text_body =~ "Elias Guitarrista"
        assert email.text_body =~ "Culto da Manhã"
        assert email.text_body =~ "/swaps"
      end)
    end
  end

  # O aceite gravado é da US 4.3, e o notificador não grava nada: para ele o
  # pedido aceito é só um struct com `status` e `mode` no lugar.
  defp aceito(pedido, mode), do: %{pedido | status: :accepted, mode: mode}
end
