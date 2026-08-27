defmodule ChurchBandsWeb.SwapLive.FormTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
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

  # O Elias toca guitarra na Banda A, que tem o "Culto da Noite" marcado; o
  # Rafael toca guitarra na Banda B, que tem o "Culto da Manhã". É o cenário
  # dos seeds, e o de quase todo teste desta tela.
  defp cenario(_contexto) do
    elias = member_fixture(%{name: "Elias Guitarrista"})
    rafael = member_fixture(%{name: "Rafael Guitarrista"})

    banda_a = banda_chamada("Banda A")
    banda_b = banda_chamada("Banda B")

    culto_noite = event_fixture(%{title: "Culto da Noite", starts_at: in_days(3)})
    culto_manha = event_fixture(%{title: "Culto da Manhã", starts_at: in_days(4)})

    %{
      elias: elias,
      rafael: rafael,
      banda_a: banda_a,
      banda_b: banda_b,
      elias_a: band_member_fixture(%{band: banda_a, user: elias, instrument: "Guitarra"}),
      rafael_b: band_member_fixture(%{band: banda_b, user: rafael, instrument: "Guitarra"}),
      culto_noite: culto_noite,
      culto_manha: culto_manha,
      escala_a: event_band_fixture(%{event: culto_noite, band: banda_a}),
      escala_b: event_band_fixture(%{event: culto_manha, band: banda_b})
    }
  end

  defp caminho(evento, member), do: ~p"/events/#{evento.id}/members/#{member.id}/swap"

  describe "o formulário" do
    setup [:cenario]

    test "mostra o alvo, a função e o dia dele", ctx do
      {:ok, _view, html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(caminho(ctx.culto_manha, ctx.rafael_b))

      assert html =~ "Pedir troca a Rafael Guitarrista"
      assert html =~ "Guitarra"
      assert html =~ "Culto da Manhã"
      assert html =~ ctx.banda_b.name
    end

    test "com uma origem só, ela vem escrita e não há seletor", ctx do
      {:ok, view, html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(caminho(ctx.culto_manha, ctx.rafael_b))

      assert html =~ "Culto da Noite"
      assert has_element?(view, "#single-origin")
      refute has_element?(view, "select#swap_request_origin_event_band_id")
    end

    test "com duas origens, a pessoa escolhe qual dia não pode", ctx do
      ensaio = event_fixture(%{title: "Ensaio da Banda A", starts_at: in_days(2)})
      event_band_fixture(%{event: ensaio, band: ctx.banda_a})

      {:ok, view, html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(caminho(ctx.culto_manha, ctx.rafael_b))

      refute has_element?(view, "#single-origin")
      assert has_element?(view, "select#swap_request_origin_event_band_id")
      assert html =~ "Ensaio da Banda A"
      assert html =~ "Culto da Noite"
    end

    test "avisa que quem recebe é quem escolhe entre cobrir e trocar", ctx do
      {:ok, view, _html} =
        ctx.conn |> log_in_user(ctx.elias) |> live(caminho(ctx.culto_manha, ctx.rafael_b))

      assert view |> element("#swap-notice") |> render() =~ "só cobrir"
    end
  end

  describe "enviar o pedido" do
    setup [:cenario]

    test "grava o pedido, avisa o alvo e leva para a lista de trocas", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)
      {:ok, view, _html} = live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert {:ok, _lista, html} =
               view
               |> form("#swap-request-form",
                 swap_request: %{origin_event_band_id: ctx.escala_a.id}
               )
               |> render_submit()
               |> follow_redirect(conn, "/swaps")

      assert html =~ "Pedido de troca enviado para Rafael Guitarrista."
      assert [pedido] = Swaps.list_sent(ctx.elias)
      assert pedido.target_member_id == ctx.rafael_b.id

      assert_email_sent(fn email ->
        assert [{"", endereco}] = email.to
        assert endereco == ctx.rafael.email
      end)
    end

    test "recusa o segundo pedido pendente para o mesmo evento seu", ctx do
      {:ok, _} = Swaps.request_swap(ctx.elias, ctx.culto_manha, ctx.rafael_b, ctx.escala_a.id)

      conn = log_in_user(ctx.conn, ctx.elias)
      {:ok, view, _html} = live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert {:ok, _lista, html} =
               view
               |> form("#swap-request-form",
                 swap_request: %{origin_event_band_id: ctx.escala_a.id}
               )
               |> render_submit()
               |> follow_redirect(conn, "/swaps")

      assert html =~ "Você já tem um pedido de troca pendente para este evento."
    end

    # Os três daqui não passam pelo formulário: eles disparam o evento pelo
    # socket, que é o que faz quem tem o console aberto. O formulário desenhado
    # nunca ofereceu nenhuma destas origens.
    test "não grava nada quando a origem forjada é um evento em que a pessoa não toca", ctx do
      alheio = event_fixture(%{starts_at: in_days(5)})
      escala_alheia = event_band_fixture(%{event: alheio, band: ctx.banda_b})

      conn = log_in_user(ctx.conn, ctx.elias)
      {:ok, view, _html} = live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert {:ok, _evento, html} =
               view
               |> render_submit("request", %{
                 "swap_request" => %{"origin_event_band_id" => to_string(escala_alheia.id)}
               })
               |> follow_redirect(conn, "/events/#{ctx.culto_manha.id}")

      assert html =~ "Você não pode pedir troca com este integrante."
      assert Swaps.list_sent(ctx.elias) == []
    end

    test "não grava nada quando a origem forjada é o próprio evento do alvo", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)
      {:ok, view, _html} = live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert {:ok, _evento, html} =
               view
               |> render_submit("request", %{
                 "swap_request" => %{"origin_event_band_id" => to_string(ctx.escala_b.id)}
               })
               |> follow_redirect(conn, "/events/#{ctx.culto_manha.id}")

      assert html =~ "Você não pode pedir troca com este integrante."
      assert Swaps.list_sent(ctx.elias) == []
    end

    test "não grava nada quando o que veio no lugar da origem não é um id", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)
      {:ok, view, _html} = live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert {:ok, _evento, html} =
               view
               |> render_submit("request", %{
                 "swap_request" => %{"origin_event_band_id" => "banana"}
               })
               |> follow_redirect(conn, "/events/#{ctx.culto_manha.id}")

      assert html =~ "Você não pode pedir troca com este integrante."
      assert Swaps.list_sent(ctx.elias) == []
    end
  end

  describe "quem a tela recusa antes de abrir" do
    setup [:cenario]

    test "visitante é mandado para o login", ctx do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(ctx.conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert flash["error"] =~ "precisa entrar"
    end

    test "evento inventado devolve ao calendário", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               live(conn, ~p"/events/abacaxi/members/#{ctx.rafael_b.id}/swap")

      assert flash["error"] == "Evento não encontrado."
    end

    test "vínculo inventado devolve ao evento", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{to: caminho_de_volta, flash: flash}}} =
               live(conn, ~p"/events/#{ctx.culto_manha.id}/members/abacaxi/swap")

      assert caminho_de_volta == "/events/#{ctx.culto_manha.id}"
      assert flash["error"] == "Integrante não encontrado."
    end

    test "vínculo de banda que não toca neste evento é o mesmo 'não encontrado'", ctx do
      forasteiro = band_member_fixture(%{band: banda_chamada("Banda C"), instrument: "Guitarra"})
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, caminho(ctx.culto_manha, forasteiro))

      assert flash["error"] == "Integrante não encontrado."
    end

    test "função diferente recebe a recusa que diz o motivo", ctx do
      baixo = band_member_fixture(%{band: ctx.banda_b, instrument: "Baixo"})
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{flash: flash}}} = live(conn, caminho(ctx.culto_manha, baixo))

      assert flash["error"] == "Vocês não fazem a mesma função."
    end

    test "pedir troca a si mesmo é recusado", ctx do
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, caminho(ctx.culto_noite, ctx.elias_a))

      assert flash["error"] == "Você não pode pedir troca com este integrante."
    end

    test "evento do alvo cancelado é recusado", ctx do
      {:ok, cancelado} = Schedule.cancel_event(ctx.culto_manha)
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{flash: flash}}} = live(conn, caminho(cancelado, ctx.rafael_b))

      assert flash["error"] == "Você não pode pedir troca com este integrante."
    end

    test "quem não tem evento futuro seu com aquela função é recusado", ctx do
      {:ok, _} = Schedule.cancel_event(ctx.culto_noite)
      conn = log_in_user(ctx.conn, ctx.elias)

      assert {:error, {:redirect, %{flash: flash}}} =
               live(conn, caminho(ctx.culto_manha, ctx.rafael_b))

      assert flash["error"] == "Você não pode pedir troca com este integrante."
    end
  end
end
