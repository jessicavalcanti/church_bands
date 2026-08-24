defmodule ChurchBandsWeb.PasswordResetLive.ResetTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts

  @valid %{"password" => "novasenha123", "password_confirmation" => "novasenha123"}

  describe "link válido" do
    setup do
      user = member_fixture()
      {token, reset_token} = password_reset_token_fixture(user)

      %{user: user, token: token, reset_token: reset_token}
    end

    test "mostra o formulário com o e-mail da conta", %{conn: conn, token: token, user: user} do
      {:ok, view, html} = live(conn, ~p"/password/reset/#{token}")

      assert has_element?(view, "#password-reset-form")
      assert html =~ user.email
      refute has_element?(view, "#invalid-reset-token")
    end

    test "redefine a senha e leva para o login", %{conn: conn, token: token, user: user} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      view |> form("#password-reset-form", user: @valid) |> render_submit()

      assert {to, flash} = assert_redirect(view)
      assert to == ~p"/login?#{[email: user.email]}"
      assert flash["info"] =~ "Senha redefinida"
    end

    test "a senha nova vale no login em seguida", %{conn: conn, token: token, user: user} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")
      view |> form("#password-reset-form", user: @valid) |> render_submit()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "novasenha123"}
        })

      assert Accounts.get_user_by_session_token(get_session(conn, :user_token)).id == user.id
    end

    test "recusa senha fraca sem trocar nada", %{conn: conn, token: token, user: user} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      html =
        view
        |> form("#password-reset-form",
          user: %{"password" => "abc", "password_confirmation" => "abc"}
        )
        |> render_submit()

      assert html =~ "password-reset-form"
      assert {:ok, _} = Accounts.authenticate_user(user.email, "senha123456")
    end

    test "aponta a senha fraca enquanto a pessoa digita", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      html =
        view
        |> form("#password-reset-form",
          user: %{"password" => "curta", "password_confirmation" => "curta"}
        )
        |> render_change()

      assert html =~ "precisa ter ao menos"
      assert has_element?(view, "#password-reset-form")
    end

    test "o link usado em outra aba deixa de valer nesta", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      # A outra aba redefine a senha primeiro; o token morre no consumo.
      assert {:ok, _} = Accounts.reset_password(token, @valid)

      view
      |> form("#password-reset-form",
        user: %{
          "password" => "outrasenha12",
          "password_confirmation" => "outrasenha12"
        }
      )
      |> render_submit()

      assert has_element?(view, "#invalid-reset-token")
      refute has_element?(view, "#password-reset-form")
    end

    test "a sessão aberta em outro navegador para de valer", %{
      conn: conn,
      token: token,
      user: user
    } do
      # Quem pede uma senha nova costuma estar fazendo isso porque desconfia
      # que entraram na conta. A sessão do invasor precisa cair junto.
      outro_navegador = log_in_user(Phoenix.ConnTest.build_conn(), user)
      assert html_response(get(outro_navegador, ~p"/profile"), 200)

      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")
      view |> form("#password-reset-form", user: @valid) |> render_submit()

      assert redirected_to(get(outro_navegador, ~p"/profile")) == ~p"/login"
    end

    test "derruba na hora a aba que estava aberta", %{conn: conn, token: token, user: user} do
      # O tópico é o da sessão, e não o da pessoa (DT-12): quem estava com a
      # aba aberta é uma sessão específica, e é o token dela que nomeia o
      # tópico em que o broadcast cai.
      aberta = log_in_user(Phoenix.ConnTest.build_conn(), user)
      live_socket_id = Plug.Conn.get_session(aberta, :live_socket_id)
      ChurchBandsWeb.Endpoint.subscribe(live_socket_id)

      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")
      view |> form("#password-reset-form", user: @valid) |> render_submit()

      assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    end

    test "recusa confirmação diferente", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      html =
        view
        |> form("#password-reset-form",
          user: %{"password" => "novasenha123", "password_confirmation" => "outrasenha123"}
        )
        |> render_submit()

      assert html =~ "não confere com a senha"
    end
  end

  describe "link que não vale mais" do
    test "expirado cai na tela de link inválido", %{conn: conn} do
      user = member_fixture()
      {token, _} = password_reset_token_fixture(user, %{expires_at: minutes_ago(1)})

      {:ok, view, html} = live(conn, ~p"/password/reset/#{token}")

      assert has_element?(view, "#invalid-reset-token")
      refute has_element?(view, "#password-reset-form")
      assert html =~ "Link inválido"
    end

    test "já usado cai na tela de link inválido", %{conn: conn} do
      user = member_fixture()
      {token, _} = password_reset_token_fixture(user, %{used_at: minutes_ago(1)})

      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")

      assert has_element?(view, "#invalid-reset-token")
    end

    test "token inventado cai na tela de link inválido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/password/reset/token-inventado")

      assert has_element?(view, "#invalid-reset-token")
    end

    test "reusar o link depois de trocar a senha é recusado", %{conn: conn} do
      user = member_fixture()
      {token, _} = password_reset_token_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/password/reset/#{token}")
      view |> form("#password-reset-form", user: @valid) |> render_submit()

      {:ok, reused, _html} = live(conn, ~p"/password/reset/#{token}")

      assert has_element?(reused, "#invalid-reset-token")
      assert {:ok, _} = Accounts.authenticate_user(user.email, "novasenha123")
    end
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now() |> DateTime.add(-minutes, :minute) |> DateTime.truncate(:second)
  end
end
