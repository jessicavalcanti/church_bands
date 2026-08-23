defmodule ChurchBandsWeb.PageControllerTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures

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
end
