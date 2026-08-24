defmodule ChurchBandsWeb.UserAuthTest do
  @moduledoc """
  Os plugs de sessão de `ChurchBandsWeb.UserAuth`.

  A tela de login e o POST que abre a sessão são testados em
  `ChurchBandsWeb.SessionControllerTest`; aqui ficam os comportamentos que só
  aparecem olhando o plug de perto — o token gravado na sessão, a derrubada das
  LiveViews abertas ao sair e a recusa de quem não está logado.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Ecto.Query

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.UserToken
  alias ChurchBands.Repo
  alias ChurchBandsWeb.UserAuth

  @new_password %{"password" => "novasenha123", "password_confirmation" => "novasenha123"}

  setup %{conn: conn} do
    %{conn: Phoenix.ConnTest.init_test_session(conn, %{})}
  end

  describe "log_in_user/2" do
    test "grava o token da sessão e o id do socket LiveView", %{conn: conn} do
      user = member_fixture()

      conn = UserAuth.log_in_user(conn, user)

      token = get_session(conn, :user_token)

      assert is_binary(token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "cada entrada abre uma sessão própria, com token próprio", %{conn: conn} do
      user = member_fixture()

      casa = UserAuth.log_in_user(conn, user) |> get_session(:user_token)
      trabalho = UserAuth.log_in_user(conn, user) |> get_session(:user_token)

      refute casa == trabalho
      assert Accounts.get_user_by_session_token(casa).id == user.id
      assert Accounts.get_user_by_session_token(trabalho).id == user.id
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
      conn = UserAuth.log_in_user(conn, user)
      live_socket_id = get_session(conn, :live_socket_id)
      ChurchBandsWeb.Endpoint.subscribe(live_socket_id)

      UserAuth.log_out_user(conn)

      assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
    end

    test "sair apaga o token desta sessão, e só o dela", %{conn: conn} do
      user = member_fixture()
      casa = UserAuth.log_in_user(conn, user)
      trabalho = UserAuth.log_in_user(conn, user)
      token_do_trabalho = get_session(trabalho, :user_token)

      UserAuth.log_out_user(casa)

      refute Accounts.get_user_by_session_token(get_session(casa, :user_token))
      assert Accounts.get_user_by_session_token(token_do_trabalho).id == user.id
    end

    test "limpa a sessão de quem não tinha socket aberto", %{conn: conn} do
      conn = conn |> put_session(:user_token, "sem sessão") |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
    end
  end

  describe "disconnect_sessions/1" do
    test "derruba a LiveView aberta de cada sessão que morreu", %{conn: conn} do
      user = member_fixture()
      casa = UserAuth.log_in_user(conn, user)
      trabalho = UserAuth.log_in_user(conn, user)

      for socket_id <- [
            get_session(casa, :live_socket_id),
            get_session(trabalho, :live_socket_id)
          ] do
        ChurchBandsWeb.Endpoint.subscribe(socket_id)
      end

      UserAuth.disconnect_sessions([
        %{token: get_session(casa, :user_token)},
        %{token: get_session(trabalho, :user_token)}
      ])

      topico_de_casa = get_session(casa, :live_socket_id)
      topico_do_trabalho = get_session(trabalho, :live_socket_id)

      assert_receive %Phoenix.Socket.Broadcast{topic: ^topico_de_casa, event: "disconnect"}
      assert_receive %Phoenix.Socket.Broadcast{topic: ^topico_do_trabalho, event: "disconnect"}
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
      {:ok, _} = Accounts.reset_password(token, @new_password)

      conn = UserAuth.fetch_current_user(conn, [])

      assert is_nil(conn.assigns.current_user)
    end

    test "a sessão com um token inventado não vale", %{conn: conn} do
      conn =
        conn
        |> put_session(:user_token, :crypto.strong_rand_bytes(32))
        |> UserAuth.fetch_current_user([])

      assert is_nil(conn.assigns.current_user)
    end

    test "a sessão que passou do prazo não vale", %{conn: conn} do
      user = member_fixture()
      conn = UserAuth.log_in_user(conn, user)

      expire_session(get_session(conn, :user_token))

      conn = UserAuth.fetch_current_user(conn, [])

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

  # Envelhece a linha da sessão para além do prazo, que é o que o relógio faria
  # em duas semanas: é assim que se exercita o corte de validade sem esperar
  # por ele.
  defp expire_session(token) do
    dias = UserToken.session_validity_in_days() + 1
    vencida = DateTime.utc_now() |> DateTime.add(-dias, :day) |> DateTime.truncate(:second)

    Repo.update_all(from(t in UserToken, where: t.token == ^token), set: [inserted_at: vencida])
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
