defmodule ChurchBandsWeb.SessionLiveTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "tela de login" do
    test "mostra o formulário para visitante", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, "#login-form")
      assert has_element?(view, "#login-form input[name='user[email]']")
      assert has_element?(view, "#login-form input[name='user[password]'][type='password']")
      assert has_element?(view, "#login-button")
    end

    test "abre com a ilustração das telas públicas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, "#worship-illustration[aria-hidden='true']")
    end

    test "o formulário posta para a rota que abre a sessão", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, "#login-form[action='/login'][method='post']")
    end

    test "pré-preenche o e-mail recebido na query string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login?#{[email: "pessoa@exemplo.com"]}")

      assert has_element?(view, "#login-form input[value='pessoa@exemplo.com']")
    end

    test "manda quem já está logado para a home", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/login")
    end
  end
end
