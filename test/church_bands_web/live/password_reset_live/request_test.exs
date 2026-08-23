defmodule ChurchBandsWeb.PasswordResetLive.RequestTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias ChurchBands.Accounts.PasswordResetToken
  alias ChurchBands.Repo

  @limit Application.compile_env!(:church_bands, ChurchBands.RateLimit)[:password_reset][:limit]

  describe "tela de pedido" do
    test "é pública e mostra o formulário", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/password/forgot")

      assert has_element?(view, "#password-reset-request-form")
      assert has_element?(view, "#request-reset-button")
    end

    test "o login leva até ela", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, "#forgot-password-link")

      assert {:ok, _view, html} =
               view |> element("#forgot-password-link") |> render_click() |> follow_redirect(conn)

      assert html =~ "Esqueci minha senha"
    end
  end

  describe "pedido de redefinição" do
    test "envia o link para quem tem conta ativa", %{conn: conn} do
      user = member_fixture()
      {:ok, view, _html} = live(conn, ~p"/password/forgot")

      html =
        view
        |> form("#password-reset-request-form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "Se houver uma conta ativa com esse e-mail"
      assert has_element?(view, "#reset-requested")

      assert_email_sent(fn email ->
        assert {_, to} = hd(email.to)
        assert to == user.email
      end)
    end

    test "responde igual para e-mail sem conta, sem enviar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/password/forgot")

      html =
        view
        |> form("#password-reset-request-form", user: %{email: "ninguem@exemplo.com"})
        |> render_submit()

      assert html =~ "Se houver uma conta ativa com esse e-mail"
      assert Repo.aggregate(PasswordResetToken, :count) == 0
      assert_no_email_sent()
    end

    test "recusa novos pedidos depois de muitos seguidos, sem enviar nada", %{conn: conn} do
      user = member_fixture()

      for _ <- 1..@limit do
        pedir_link(conn, user.email)
        assert_email_sent()
      end

      html = pedir_link(conn, user.email)

      assert html =~ "Muitas tentativas"
      assert_no_email_sent()
    end
  end

  # Cada pedido sai de uma tela recém-aberta porque, depois de enviar, o
  # formulário dá lugar ao aviso de "verifique seu e-mail".
  defp pedir_link(conn, email) do
    {:ok, view, _html} = live(conn, ~p"/password/forgot")

    view
    |> form("#password-reset-request-form", user: %{email: email})
    |> render_submit()
  end
end
