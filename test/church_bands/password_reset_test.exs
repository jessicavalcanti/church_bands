defmodule ChurchBands.PasswordResetTest do
  @moduledoc """
  Recuperação de senha (US 1.7): pedido do link, prazo, uso único e a troca
  em si.
  """
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.PasswordResetToken

  @new_password %{"password" => "novasenha123", "password_confirmation" => "novasenha123"}

  describe "request_password_reset/1" do
    test "grava o token e envia o link para quem tem conta ativa" do
      user = member_fixture()

      assert :ok = Accounts.request_password_reset(user.email)

      assert %PasswordResetToken{} =
               reset_token = Repo.get_by(PasswordResetToken, user_id: user.id)

      assert is_nil(reset_token.used_at)
      assert PasswordResetToken.usable?(reset_token)

      assert_email_sent(fn email ->
        assert {_, to} = hd(email.to)
        assert to == user.email
        assert email.text_body =~ "/password/reset/"
      end)
    end

    test "o token do link não é o que fica no banco" do
      user = member_fixture()
      Accounts.request_password_reset(user.email)

      reset_token = Repo.get_by!(PasswordResetToken, user_id: user.id)

      assert_email_sent(fn email ->
        assert email.text_body =~ "/password/reset/"
        assert not (email.text_body =~ reset_token.token_hash)
      end)
    end

    test "o link expira em 1 hora" do
      user = member_fixture()
      Accounts.request_password_reset(user.email)

      reset_token = Repo.get_by!(PasswordResetToken, user_id: user.id)

      expected =
        DateTime.add(DateTime.utc_now(), PasswordResetToken.validity_in_minutes(), :minute)

      assert_in_delta DateTime.diff(reset_token.expires_at, expected), 0, 5
    end

    test "não diferencia e-mail inexistente: devolve :ok sem enviar nada" do
      assert :ok = Accounts.request_password_reset("ninguem@exemplo.com")

      assert Repo.aggregate(PasswordResetToken, :count) == 0
      assert_no_email_sent()
    end

    test "convite ainda não aceito não gera redefinição" do
      invite = invite_fixture()

      # O convite já deixou o próprio e-mail na caixa; tirá-lo da frente é o
      # que deixa `assert_no_email_sent/0` falar só sobre a redefinição.
      assert_email_sent(fn email -> assert email.subject =~ "convite" end)

      assert :ok = Accounts.request_password_reset(invite.email)

      assert Repo.aggregate(PasswordResetToken, :count) == 0
      assert_no_email_sent()
    end

    test "e-mail em branco ou de outro tipo não estoura" do
      assert :ok = Accounts.request_password_reset("")
      assert :ok = Accounts.request_password_reset(nil)
      assert_no_email_sent()
    end
  end

  describe "get_usable_reset_token/1" do
    test "devolve o token válido com o usuário pré-carregado" do
      user = member_fixture()
      {token, _} = password_reset_token_fixture(user)

      assert %PasswordResetToken{user: found} = Accounts.get_usable_reset_token(token)
      assert found.id == user.id
    end

    test "recusa token expirado, usado ou inventado" do
      user = member_fixture()

      {expired, _} = password_reset_token_fixture(user, %{expires_at: minutes_ago(1)})
      {used, _} = password_reset_token_fixture(user, %{used_at: minutes_ago(1)})

      assert is_nil(Accounts.get_usable_reset_token(expired))
      assert is_nil(Accounts.get_usable_reset_token(used))
      assert is_nil(Accounts.get_usable_reset_token("token-inventado"))
    end

    test "recusa o que nem é token, como o `nil` de uma rota sem parâmetro" do
      assert is_nil(Accounts.get_usable_reset_token(nil))
    end
  end

  describe "reset_password/2" do
    setup do
      user = member_fixture()
      {token, reset_token} = password_reset_token_fixture(user)

      %{user: user, token: token, reset_token: reset_token}
    end

    test "troca a senha e permite o login com a nova", %{user: user, token: token} do
      assert {:ok, updated} = Accounts.reset_password(token, @new_password)
      assert updated.id == user.id

      assert {:ok, _} = Accounts.authenticate_user(user.email, "novasenha123")

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(user.email, "senha123456")
    end

    test "marca o token como usado", %{token: token, reset_token: reset_token} do
      assert {:ok, _} = Accounts.reset_password(token, @new_password)

      assert Repo.get!(PasswordResetToken, reset_token.id).used_at
    end

    test "o mesmo link não serve duas vezes", %{user: user, token: token} do
      assert {:ok, _} = Accounts.reset_password(token, @new_password)

      assert {:error, :invalid_token} =
               Accounts.reset_password(token, %{
                 "password" => "terceirasenha1",
                 "password_confirmation" => "terceirasenha1"
               })

      assert {:ok, _} = Accounts.authenticate_user(user.email, "novasenha123")
    end

    test "invalida os outros links pendentes do mesmo usuário", %{user: user, token: token} do
      {outro, outro_token} = password_reset_token_fixture(user)

      assert {:ok, _} = Accounts.reset_password(token, @new_password)

      assert Repo.get!(PasswordResetToken, outro_token.id).used_at
      assert is_nil(Accounts.get_usable_reset_token(outro))
    end

    test "recusa link expirado", %{user: user} do
      {token, _} = password_reset_token_fixture(user, %{expires_at: minutes_ago(1)})

      assert {:error, :invalid_token} = Accounts.reset_password(token, @new_password)
      assert {:ok, _} = Accounts.authenticate_user(user.email, "senha123456")
    end

    test "recusa senha fraca sem consumir o token", %{
      user: user,
      token: token,
      reset_token: reset_token
    } do
      assert {:error, changeset} = Accounts.reset_password(token, %{"password" => "abc"})

      assert %{password: _} = errors_on(changeset)
      assert is_nil(Repo.get!(PasswordResetToken, reset_token.id).used_at)
      assert {:ok, _} = Accounts.authenticate_user(user.email, "senha123456")
    end

    test "exige a confirmação da senha", %{token: token} do
      assert {:error, changeset} =
               Accounts.reset_password(token, %{
                 "password" => "novasenha123",
                 "password_confirmation" => "outrasenha123"
               })

      assert "não confere com a senha" in errors_on(changeset).password_confirmation
    end
  end

  defp minutes_ago(minutes) do
    DateTime.utc_now() |> DateTime.add(-minutes, :minute) |> DateTime.truncate(:second)
  end
end
