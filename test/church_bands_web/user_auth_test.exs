defmodule ChurchBandsWeb.UserAuthTest do
  @moduledoc """
  Os plugs de sessão de `ChurchBandsWeb.UserAuth`.

  A tela de login e o POST que abre a sessão são testados em
  `ChurchBandsWeb.SessionControllerTest`; aqui ficam os comportamentos que só
  aparecem olhando o plug de perto — o id do socket gravado na sessão, a
  derrubada das LiveViews abertas ao sair e a recusa de quem não está logado.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures

  alias ChurchBands.Accounts
  alias ChurchBandsWeb.UserAuth

  @new_password %{"password" => "novasenha123", "password_confirmation" => "novasenha123"}

  setup %{conn: conn} do
    %{conn: Phoenix.ConnTest.init_test_session(conn, %{})}
  end

  describe "log_in_user/2" do
    test "grava o usuário e o id do socket LiveView na sessão", %{conn: conn} do
      user = member_fixture()

      conn = UserAuth.log_in_user(conn, user)

      assert get_session(conn, :user_id) == user.id
      assert get_session(conn, :live_socket_id) == "users_sessions:#{user.id}"
      assert get_session(conn, :auth_fingerprint) == Accounts.session_fingerprint(user)
    end

    test "renova a sessão, descartando o que havia antes", %{conn: conn} do
      user = member_fixture()

      conn = conn |> put_session(:rastro, "de antes") |> UserAuth.log_in_user(user)

      refute get_session(conn, :rastro)
    end
  end

  describe "log_out_user/1" do
    test "desconecta as LiveViews abertas da sessão encerrada", %{conn: conn} do
      user = member_fixture()
      live_socket_id = "users_sessions:#{user.id}"
      ChurchBandsWeb.Endpoint.subscribe(live_socket_id)

      conn |> UserAuth.log_in_user(user) |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    end

    test "limpa a sessão de quem não tinha socket aberto", %{conn: conn} do
      conn = conn |> put_session(:user_id, 1) |> UserAuth.log_out_user()

      refute get_session(conn, :user_id)
    end
  end

  describe "disconnect_sessions/1" do
    test "derruba as LiveViews abertas do usuário, em qualquer navegador" do
      user = member_fixture()
      live_socket_id = "users_sessions:#{user.id}"
      ChurchBandsWeb.Endpoint.subscribe(live_socket_id)

      UserAuth.disconnect_sessions(user)

      assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    end
  end

  describe "fetch_current_user/2" do
    test "carrega em current_user o usuário da sessão", %{conn: conn} do
      user = member_fixture()

      conn = conn |> UserAuth.log_in_user(user) |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "deixa current_user em nil quando não há sessão", %{conn: conn} do
      conn = UserAuth.fetch_current_user(conn, [])

      assert is_nil(conn.assigns.current_user)
    end

    test "a sessão aberta com a senha antiga para de valer", %{conn: conn} do
      user = member_fixture()
      conn = UserAuth.log_in_user(conn, user)

      {token, _reset_token} = password_reset_token_fixture(user)
      {:ok, _user} = Accounts.reset_password(token, @new_password)

      conn = UserAuth.fetch_current_user(conn, [])

      assert is_nil(conn.assigns.current_user)
    end

    test "a sessão sem a impressão digital da senha não vale", %{conn: conn} do
      user = member_fixture()

      conn = conn |> put_session(:user_id, user.id) |> UserAuth.fetch_current_user([])

      assert is_nil(conn.assigns.current_user)
    end

    test "a sessão de uma conta que não existe mais não vale", %{conn: conn} do
      user = member_fixture()
      conn = UserAuth.log_in_user(conn, user)
      ChurchBands.Repo.delete!(user)

      conn = UserAuth.fetch_current_user(conn, [])

      assert is_nil(conn.assigns.current_user)
    end
  end

  describe "require_authenticated_user/2" do
    test "deixa a requisição seguir quando há usuário logado", %{conn: conn} do
      conn =
        conn |> assign(:current_user, member_fixture()) |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "interrompe e manda para o login quem não está logado", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.fetch_flash([])
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "precisa entrar"
    end
  end
end
