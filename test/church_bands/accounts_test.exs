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
