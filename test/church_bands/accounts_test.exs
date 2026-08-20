defmodule ChurchBands.AccountsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.Invite

  describe "create_invite/2" do
    test "registra o convite como pendente e envia o e-mail de ativação" do
      leader = worship_leader_fixture()

      assert {:ok, %Invite{} = invite} =
               Accounts.create_invite(%{"email" => "nova@exemplo.com"}, leader)

      assert invite.email == "nova@exemplo.com"
      assert invite.status == :pending
      assert invite.invited_by_id == leader.id
      assert is_binary(invite.token)
      assert Invite.usable?(invite)

      assert_email_sent(fn email ->
        assert {_, "nova@exemplo.com"} = hd(email.to)
        assert email.text_body =~ invite.token
      end)
    end

    test "define o prazo de validade em 7 dias" do
      invite = invite_fixture()
      expected = DateTime.add(DateTime.utc_now(), Invite.validity_in_days(), :day)

      assert_in_delta DateTime.diff(invite.expires_at, expected), 0, 5
    end

    test "recusa e-mail que já possui conta no sistema" do
      leader = worship_leader_fixture()
      existing = member_fixture()

      assert {:error, changeset} = Accounts.create_invite(%{"email" => existing.email}, leader)
      assert "já possui uma conta no sistema" in errors_on(changeset).email
    end

    test "recusa e-mail que já possui conta ignorando maiúsculas/minúsculas" do
      leader = worship_leader_fixture()
      existing = member_fixture(%{email: "Pessoa@Exemplo.com"})

      assert {:error, changeset} =
               Accounts.create_invite(%{"email" => String.upcase(existing.email)}, leader)

      assert "já possui uma conta no sistema" in errors_on(changeset).email
    end

    test "recusa segundo convite pendente para o mesmo e-mail" do
      leader = worship_leader_fixture()
      invite = invite_fixture(%{invited_by: leader})

      assert {:error, changeset} = Accounts.create_invite(%{"email" => invite.email}, leader)
      assert "já possui um convite pendente" in errors_on(changeset).email
    end

    test "permite novo convite depois que o anterior foi cancelado" do
      leader = worship_leader_fixture()
      invite = invite_fixture(%{invited_by: leader})
      {:ok, _} = Accounts.cancel_invite(invite)

      assert {:ok, %Invite{status: :pending}} =
               Accounts.create_invite(%{"email" => invite.email}, leader)
    end

    test "recusa e-mail em branco ou inválido" do
      leader = worship_leader_fixture()

      assert {:error, changeset} = Accounts.create_invite(%{"email" => ""}, leader)
      assert "can't be blank" in errors_on(changeset).email

      assert {:error, changeset} = Accounts.create_invite(%{"email" => "sem-arroba"}, leader)
      assert "precisa ser um e-mail válido" in errors_on(changeset).email
    end
  end

  describe "resend_invite/1" do
    test "gera um novo token, renova o prazo e reenvia o e-mail" do
      invite = invite_fixture()
      # consome o e-mail disparado pela criação do convite
      assert_email_sent(fn email -> assert email.text_body =~ invite.token end)

      assert {:ok, resent} = Accounts.resend_invite(invite)
      assert resent.token != invite.token
      assert resent.status == :pending
      assert DateTime.compare(resent.expires_at, DateTime.utc_now()) == :gt

      assert_email_sent(fn email -> assert email.text_body =~ resent.token end)
    end

    test "devolve um convite expirado para pendente" do
      invite = expired_invite()

      assert {:ok, resent} = Accounts.resend_invite(invite)
      assert resent.status == :pending
      assert Invite.usable?(resent)
    end

    test "recusa reenvio de convite já aceito" do
      invite = accepted_invite()

      assert {:error, :already_accepted} = Accounts.resend_invite(invite)
    end
  end

  describe "cancel_invite/1" do
    test "marca o convite como cancelado" do
      invite = invite_fixture()

      assert {:ok, cancelled} = Accounts.cancel_invite(invite)
      assert cancelled.status == :cancelled
      refute Invite.usable?(cancelled)
    end

    test "cancelar duas vezes é idempotente" do
      invite = invite_fixture()
      {:ok, cancelled} = Accounts.cancel_invite(invite)

      assert {:ok, %Invite{status: :cancelled}} = Accounts.cancel_invite(cancelled)
    end

    test "recusa cancelamento de convite já aceito" do
      invite = accepted_invite()

      assert {:error, :already_accepted} = Accounts.cancel_invite(invite)
    end
  end

  describe "expire_overdue_invites/0" do
    test "marca como expirados apenas os convites pendentes fora do prazo" do
      # o convite válido é criado primeiro porque `create_invite/2` já dispara
      # uma varredura de expiração
      valid = invite_fixture()
      overdue = expired_invite()

      assert Accounts.expire_overdue_invites() == 1
      assert Repo.get!(Invite, overdue.id).status == :expired
      assert Repo.get!(Invite, valid.id).status == :pending
    end

    test "list_invites/0 devolve os status já atualizados" do
      overdue = expired_invite()

      assert [listed] = Accounts.list_invites()
      assert listed.id == overdue.id
      assert listed.status == :expired
      assert listed.invited_by.id == overdue.invited_by_id
    end
  end

  describe "full_access?/1" do
    test "vale para Pastor e Líder de Louvor" do
      assert Accounts.full_access?(pastor_fixture())
      assert Accounts.full_access?(worship_leader_fixture())
    end

    test "não vale para músico comum nem para visitante" do
      refute Accounts.full_access?(member_fixture())
      refute Accounts.full_access?(nil)
    end
  end

  describe "accept_invite/2" do
    @valid_activation %{
      "name" => "Nova Pessoa",
      "password" => "senha123456",
      "password_confirmation" => "senha123456"
    }

    test "cria a conta com o e-mail do convite e marca o convite como aceito" do
      invite = invite_fixture()

      assert {:ok, user} = Accounts.accept_invite(invite, @valid_activation)
      assert user.email == invite.email
      assert user.name == "Nova Pessoa"
      assert user.global_role == :member
      assert user.confirmed_at
      assert is_binary(user.hashed_password)

      assert Repo.get!(Invite, invite.id).status == :accepted
    end

    test "ignora um e-mail enviado no formulário: vale sempre o do convite" do
      invite = invite_fixture()
      attrs = Map.put(@valid_activation, "email", "outra@exemplo.com")

      assert {:ok, user} = Accounts.accept_invite(invite, attrs)
      assert user.email == invite.email
    end

    test "recusa senha fora dos critérios mínimos" do
      invite = invite_fixture()

      assert {:error, changeset} =
               Accounts.accept_invite(invite, %{
                 "name" => "Nova Pessoa",
                 "password" => "abc",
                 "password_confirmation" => "abc"
               })

      assert "should be at least 8 character(s)" in errors_on(changeset).password
      assert "precisa conter ao menos um número" in errors_on(changeset).password
    end

    test "recusa senha só com letras ou só com números" do
      invite = invite_fixture()

      assert {:error, changeset} =
               Accounts.accept_invite(invite, %{
                 "name" => "Nova Pessoa",
                 "password" => "somenteletras",
                 "password_confirmation" => "somenteletras"
               })

      assert "precisa conter ao menos um número" in errors_on(changeset).password

      assert {:error, changeset} =
               Accounts.accept_invite(invite, %{
                 "name" => "Nova Pessoa",
                 "password" => "1234567890",
                 "password_confirmation" => "1234567890"
               })

      assert "precisa conter ao menos uma letra" in errors_on(changeset).password
    end

    test "recusa quando a confirmação não confere" do
      invite = invite_fixture()

      assert {:error, changeset} =
               Accounts.accept_invite(invite, %{
                 "name" => "Nova Pessoa",
                 "password" => "senha123456",
                 "password_confirmation" => "outra123456"
               })

      assert "não confere com a senha" in errors_on(changeset).password_confirmation
    end

    test "recusa quando o nome está em branco" do
      invite = invite_fixture()
      attrs = Map.put(@valid_activation, "name", "")

      assert {:error, changeset} = Accounts.accept_invite(invite, attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "não cria conta quando o convite falha e não deixa resíduo" do
      invite = invite_fixture()
      attrs = Map.put(@valid_activation, "password", "abc")

      assert {:error, %Ecto.Changeset{}} = Accounts.accept_invite(invite, attrs)
      refute Accounts.get_user_by_email(invite.email)
      assert Repo.get!(Invite, invite.id).status == :pending
    end

    test "recusa convite cancelado" do
      invite = invite_fixture()
      {:ok, cancelled} = Accounts.cancel_invite(invite)

      assert {:error, :invalid_invite} = Accounts.accept_invite(cancelled, @valid_activation)
      refute Accounts.get_user_by_email(invite.email)
    end

    test "recusa convite expirado" do
      invite = expired_invite()

      assert {:error, :invalid_invite} = Accounts.accept_invite(invite, @valid_activation)
      refute Accounts.get_user_by_email(invite.email)
    end

    test "recusa convite já aceito" do
      invite = accepted_invite()

      assert {:error, :invalid_invite} = Accounts.accept_invite(invite, @valid_activation)
    end
  end

  describe "get_usable_invite_by_token/1" do
    test "devolve o convite pendente dentro do prazo" do
      invite = invite_fixture()

      assert %Invite{id: id} = Accounts.get_usable_invite_by_token(invite.token)
      assert id == invite.id
    end

    test "devolve nil para token desconhecido, expirado ou cancelado" do
      refute Accounts.get_usable_invite_by_token("token-que-nao-existe")
      refute Accounts.get_usable_invite_by_token(expired_invite().token)

      {:ok, cancelled} = Accounts.cancel_invite(invite_fixture())
      refute Accounts.get_usable_invite_by_token(cancelled.token)
    end
  end

  describe "authenticate_user/2" do
    test "aceita e-mail e senha corretos" do
      user = member_fixture(%{password: "senha123456"})

      assert {:ok, authenticated} = Accounts.authenticate_user(user.email, "senha123456")
      assert authenticated.id == user.id
      assert authenticated.global_role == :member
    end

    test "aceita e-mail ignorando maiúsculas/minúsculas" do
      user = member_fixture(%{email: "Pessoa@Exemplo.com", password: "senha123456"})

      assert {:ok, authenticated} =
               Accounts.authenticate_user(String.upcase(user.email), "senha123456")

      assert authenticated.id == user.id
    end

    test "recusa senha incorreta" do
      user = member_fixture(%{password: "senha123456"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(user.email, "senha-errada-1")
    end

    test "recusa e-mail sem conta" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("ninguem@exemplo.com", "senha123456")
    end

    test "recusa conta ainda não confirmada" do
      user = member_fixture(%{password: "senha123456"})
      Repo.update!(Ecto.Changeset.change(user, confirmed_at: nil))

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(user.email, "senha123456")
    end

    test "recusa entradas que não são texto" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(nil, nil)
    end

    test "a conta criada pela ativação do convite já consegue autenticar" do
      invite = invite_fixture()
      {:ok, user} = Accounts.accept_invite(invite, @valid_activation)

      assert {:ok, authenticated} = Accounts.authenticate_user(user.email, "senha123456")
      assert authenticated.id == user.id
    end
  end

  defp expired_invite do
    invite = invite_fixture()
    past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    invite
    |> Ecto.Changeset.change(expires_at: past)
    |> Repo.update!()
  end

  defp accepted_invite do
    invite_fixture()
    |> Ecto.Changeset.change(status: :accepted)
    |> Repo.update!()
  end
end
