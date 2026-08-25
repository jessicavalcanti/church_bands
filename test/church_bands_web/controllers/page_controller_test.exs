defmodule ChurchBandsWeb.PageControllerTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures

  test "visitante vê o convite para entrar", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Grupo de Louvor"
    assert html =~ "home-login-button"
    refute html =~ "logout-link"
  end

  test "quem está logado vê o nome e o papel de acesso", %{conn: conn} do
    user = member_fixture(%{name: "Carla Musicista"})
    html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

    assert html =~ "Carla Musicista"
    assert html =~ "Músico(a)"
    assert html =~ "logout-link"
    refute html =~ "home-invites-button"
  end

  test "Líder de Louvor vê o atalho para os convites", %{conn: conn} do
    html = conn |> log_in_user(worship_leader_fixture()) |> get(~p"/") |> html_response(200)

    assert html =~ "home-invites-button"
    assert html =~ "Líder de Louvor"
  end

  describe "o bloco Meus próximos eventos" do
    setup do
      carla = member_fixture(%{name: "Carla Musicista"})

      ebenezer =
        band_fixture(%{name: "Banda Ebenezer #{System.unique_integer([:positive])}"})

      band_member_fixture(%{band: ebenezer, user: carla})

      %{carla: carla, ebenezer: ebenezer}
    end

    defp escalar(band, attrs) do
      evento = event_fixture(Map.put(attrs, :starts_at, in_days(3)))
      event_band_fixture(%{event: evento, band: band})
      evento
    end

    test "mostra o culto da banda, com a banda e o link para o evento", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalar(ebenezer, %{title: "Culto da Noite", location: "Templo"})

      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "Meus próximos eventos"
      assert html =~ "upcoming-event-#{culto.id}"
      assert html =~ ~s(href="/events/#{culto.id}")
      assert html =~ "Culto da Noite"
      assert html =~ "Templo"
      assert html =~ ebenezer.name
      refute html =~ "upcoming-events-empty"
    end

    test "o evento cancelado aparece riscado, com o rótulo Cancelado", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalar(ebenezer, %{title: "Culto da Noite", status: :cancelled})

      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "upcoming-event-cancelled-#{culto.id}"
      assert html =~ "Cancelado"
      assert html =~ "line-through"
    end

    # O bloco **não some** quando está vazio: uma tela que muda de forma por
    # motivo invisível faz quem olha achar que perdeu alguma coisa.
    test "sem evento nos próximos 30 dias, o bloco mostra a mensagem e o link do calendário", %{
      conn: conn,
      carla: carla
    } do
      html = conn |> log_in_user(carla) |> get(~p"/") |> html_response(200)

      assert html =~ "Meus próximos eventos"
      assert html =~ "Nenhum evento seu nos próximos 30 dias."
      assert html =~ "Ver calendário"
      assert html =~ ~s(href="/calendar")
    end

    test "quem não está em banda nenhuma vê a mesma mensagem", %{
      conn: conn,
      ebenezer: ebenezer
    } do
      escalar(ebenezer, %{title: "Culto da Noite"})

      html = conn |> log_in_user(member_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ "Nenhum evento seu nos próximos 30 dias."
      refute html =~ "Culto da Noite"
    end

    test "o visitante não vê o bloco", %{conn: conn, ebenezer: ebenezer} do
      escalar(ebenezer, %{title: "Culto da Noite"})

      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "Meus próximos eventos"
      refute html =~ "Culto da Noite"
    end
  end
end
