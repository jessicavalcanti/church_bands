defmodule ChurchBands.AccountsTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import Swoosh.TestAssertions

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Accounts.User
  alias ChurchBands.Accounts.UserToken

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

  describe "Invite" do
    test "os status possíveis de um convite" do
      assert Invite.statuses() == [:pending, :accepted, :expired, :cancelled]
    end

    test "o prazo de validade em dias" do
      assert Invite.validity_in_days() == 7
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

  describe "update_profile/2" do
    test "atualiza telefone e foto" do
      user = user_fixture()

      assert {:ok, user} =
               Accounts.update_profile(user, %{
                 "phone" => "(11) 98888-7777",
                 "photo_url" => "https://exemplo.com/foto.jpg"
               })

      assert user.phone == "(11) 98888-7777"
      assert user.photo_url == "https://exemplo.com/foto.jpg"
    end

    test "limpa os espaços em volta dos valores" do
      user = user_fixture()

      assert {:ok, user} =
               Accounts.update_profile(user, %{
                 "phone" => "  11988887777  ",
                 "photo_url" => "  https://exemplo.com/foto.jpg  "
               })

      assert user.phone == "11988887777"
      assert user.photo_url == "https://exemplo.com/foto.jpg"
    end

    test "campo em branco apaga o valor guardado" do
      user = user_fixture(%{phone: "11988887777", photo_url: "https://exemplo.com/foto.jpg"})

      assert {:ok, user} = Accounts.update_profile(user, %{"phone" => "", "photo_url" => "   "})

      assert is_nil(user.phone)
      assert is_nil(user.photo_url)
    end

    test "recusa telefone com letras" do
      user = user_fixture()

      assert {:error, changeset} = Accounts.update_profile(user, %{"phone" => "não tenho"})

      assert "pode ter apenas números, espaços e os sinais + ( ) - ." in errors_on(changeset).phone
    end

    test "recusa telefone curto demais" do
      user = user_fixture()

      assert {:error, changeset} = Accounts.update_profile(user, %{"phone" => "1234"})
      assert "precisa ter ao menos 8 números" in errors_on(changeset).phone
    end

    test "recusa foto que não é um endereço http" do
      user = user_fixture()

      assert {:error, changeset} = Accounts.update_profile(user, %{"photo_url" => "foto.jpg"})

      assert "precisa ser um endereço começando com http:// ou https://" in errors_on(changeset).photo_url
    end

    test "ignora o papel de acesso enviado junto no formulário" do
      user = member_fixture()

      assert {:ok, updated} =
               Accounts.update_profile(user, %{
                 "phone" => "11988887777",
                 "global_role" => "pastor"
               })

      assert updated.global_role == :member
      refute Accounts.full_access?(updated)
    end

    test "corrige o próprio nome" do
      user = user_fixture(%{name: "Crla Musicista"})

      assert {:ok, updated} = Accounts.update_profile(user, %{"name" => "Carla Musicista"})
      assert updated.name == "Carla Musicista"
    end

    test "recusa nome em branco e nome curto demais, em português" do
      user = user_fixture(%{name: "Carla Musicista"})

      assert {:error, changeset} = Accounts.update_profile(user, %{"name" => "   "})
      assert "não pode ficar em branco" in errors_on(changeset).name

      assert {:error, changeset} = Accounts.update_profile(user, %{"name" => "C"})
      assert "precisa ter ao menos 2 caracteres" in errors_on(changeset).name
    end

    test "ignora e-mail enviado junto no formulário" do
      user = user_fixture()
      original_email = user.email

      assert {:ok, updated} =
               Accounts.update_profile(user, %{
                 "phone" => "11988887777",
                 "email" => "outro@exemplo.com"
               })

      assert updated.email == original_email
    end
  end

  describe "change_profile/2" do
    test "devolve um changeset do próprio perfil" do
      user = user_fixture()

      assert %Ecto.Changeset{data: %ChurchBands.Accounts.User{}} = Accounts.change_profile(user)
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

  describe "User.role_label/1" do
    test "traduz os papéis de acesso para o que aparece na tela" do
      assert User.role_label(:pastor) == "Pastor(a)"
      assert User.role_label(:worship_leader) == "Líder de Louvor"
      assert User.role_label(:member) == "Músico(a)"
    end
  end

  describe "list_users/1" do
    test "lista as contas ativas em ordem alfabética" do
      user_fixture(%{name: "Carla Musicista"})
      user_fixture(%{name: "Ana Pastora"})
      user_fixture(%{name: "Bruno Líder"})

      assert ["Ana Pastora", "Bruno Líder", "Carla Musicista"] =
               Accounts.list_users() |> Enum.map(& &1.name)
    end

    test "não lista quem ainda não ativou a conta" do
      ativa = user_fixture(%{name: "Ativa"})
      user_fixture(%{name: "Pendente", confirmed_at: nil})

      assert [%{id: id}] = Accounts.list_users()
      assert id == ativa.id
    end

    test "convite ainda não aceito não aparece na lista" do
      invite = invite_fixture()

      emails = Accounts.list_users() |> Enum.map(& &1.email)

      refute invite.email in emails
    end

    test "estreita por trecho do nome, sem diferenciar maiúsculas" do
      user_fixture(%{name: "Carla Musicista"})
      user_fixture(%{name: "Bruno Líder"})

      assert ["Carla Musicista"] = Accounts.list_users("carla") |> Enum.map(& &1.name)
    end

    test "estreita por trecho do e-mail" do
      user_fixture(%{name: "Carla Musicista", email: "carla@exemplo.com"})
      user_fixture(%{name: "Bruno Líder", email: "bruno@exemplo.com"})

      assert ["Bruno Líder"] = Accounts.list_users("bruno@") |> Enum.map(& &1.name)
    end

    test "busca em branco devolve todo mundo" do
      user_fixture(%{name: "Carla Musicista"})
      user_fixture(%{name: "Bruno Líder"})

      assert length(Accounts.list_users("   ")) == 2
      assert length(Accounts.list_users(nil)) == 2
    end

    test "o curinga do SQL digitado na busca é texto, não curinga" do
      user_fixture(%{name: "Carla Musicista"})

      assert Accounts.list_users("%") == []
    end
  end

  describe "manage_users?/1" do
    test "vale para Pastor e Líder de Louvor" do
      assert Accounts.manage_users?(pastor_fixture())
      assert Accounts.manage_users?(worship_leader_fixture())
    end

    test "não vale para músico comum nem para visitante" do
      refute Accounts.manage_users?(member_fixture())
      refute Accounts.manage_users?(nil)
    end
  end

  describe "update_user/3" do
    test "corrige nome, telefone e foto de outra pessoa" do
      actor = worship_leader_fixture()
      user = member_fixture(%{name: "Crla Musicista"})

      assert {:ok, user} =
               Accounts.update_user(actor, user, %{
                 "name" => "Carla Musicista",
                 "phone" => "(11) 98888-7777",
                 "photo_url" => "https://exemplo.com/carla.jpg"
               })

      assert user.name == "Carla Musicista"
      assert user.phone == "(11) 98888-7777"
      assert user.photo_url == "https://exemplo.com/carla.jpg"
    end

    test "promove e rebaixa o papel de acesso de outra pessoa" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:ok, user} = Accounts.update_user(actor, user, %{"global_role" => "worship_leader"})
      assert user.global_role == :worship_leader

      assert {:ok, user} = Accounts.update_user(actor, user, %{"global_role" => "member"})
      assert user.global_role == :member
    end

    test "não muda o e-mail nem forjando o parâmetro" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:ok, updated} =
               Accounts.update_user(actor, user, %{
                 "name" => "Carla Musicista",
                 "email" => "outra@exemplo.com"
               })

      assert updated.email == user.email
    end

    test "não muda a senha nem forjando o parâmetro" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:ok, updated} =
               Accounts.update_user(actor, user, %{
                 "name" => "Carla Musicista",
                 "password" => "outrasenha123"
               })

      assert updated.hashed_password == user.hashed_password
    end

    test "recusa nome em branco" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:error, changeset} = Accounts.update_user(actor, user, %{"name" => "   "})
      assert "não pode ficar em branco" in errors_on(changeset).name
    end

    test "recusa nome curto demais, em português" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:error, changeset} = Accounts.update_user(actor, user, %{"name" => "C"})
      assert "precisa ter ao menos 2 caracteres" in errors_on(changeset).name
    end

    test "aplica as mesmas validações de telefone e foto do próprio perfil" do
      actor = pastor_fixture()
      user = member_fixture()

      assert {:error, changeset} = Accounts.update_user(actor, user, %{"phone" => "não tenho"})

      assert "pode ter apenas números, espaços e os sinais + ( ) - ." in errors_on(changeset).phone

      assert {:error, changeset} = Accounts.update_user(actor, user, %{"photo_url" => "foto.jpg"})

      assert "precisa ser um endereço começando com http:// ou https://" in errors_on(changeset).photo_url
    end

    test "recusa mudar o próprio papel de acesso, mesmo com acesso total" do
      # Outro Pastor existe, então a recusa não vem da trava do último acesso
      # total: vem de ser o próprio papel.
      pastor_fixture()
      actor = pastor_fixture()

      assert {:error, changeset} =
               Accounts.update_user(actor, actor, %{"global_role" => "worship_leader"})

      assert "não pode ser mudado por você mesmo — outra pessoa com acesso total precisa fazer isso" in errors_on(
               changeset
             ).global_role
    end

    test "deixa corrigir os próprios nome, telefone e foto por esta tela" do
      actor = pastor_fixture()

      assert {:ok, actor} =
               Accounts.update_user(actor, actor, %{
                 "name" => "Ana Pastora",
                 "phone" => "11988887777"
               })

      assert actor.name == "Ana Pastora"
      assert actor.phone == "11988887777"
    end

    test "recusa deixar o sistema sem nenhuma conta com acesso total" do
      # Quem é o único com acesso total só pode ser rebaixado por si mesmo —
      # não há outra pessoa autorizada a fazê-lo. É o encontro das duas travas,
      # e a mensagem que vale é a que aponta a saída: promover alguém antes.
      unico = worship_leader_fixture()

      assert {:error, changeset} =
               Accounts.update_user(unico, unico, %{"global_role" => "member"})

      assert ("não pode ser rebaixado: o sistema ficaria sem ninguém com acesso total. " <>
                "Promova outra pessoa a Pastor(a) ou Líder de Louvor antes.") in errors_on(
               changeset
             ).global_role
    end

    test "promover outra pessoa é a saída para o último com acesso total sair" do
      unico = pastor_fixture()
      musico = member_fixture()

      assert {:ok, musico} = Accounts.update_user(unico, musico, %{"global_role" => "pastor"})
      assert {:ok, unico} = Accounts.update_user(musico, unico, %{"global_role" => "member"})
      assert unico.global_role == :member
    end

    test "deixa rebaixar quando sobra outra conta com acesso total" do
      pastor = pastor_fixture()
      leader = worship_leader_fixture()

      assert {:ok, leader} = Accounts.update_user(pastor, leader, %{"global_role" => "member"})
      assert leader.global_role == :member
    end

    test "conta pendente com acesso total não segura a trava do último" do
      unico = pastor_fixture()
      user_fixture(%{global_role: :worship_leader, confirmed_at: nil})

      assert {:error, changeset} =
               Accounts.update_user(unico, unico, %{"global_role" => "member"})

      assert ("não pode ser rebaixado: o sistema ficaria sem ninguém com acesso total. " <>
                "Promova outra pessoa a Pastor(a) ou Líder de Louvor antes.") in errors_on(
               changeset
             ).global_role
    end
  end

  describe "change_user_management/3" do
    test "devolve um changeset de edição administrativa" do
      actor = pastor_fixture()
      user = member_fixture()

      assert %Ecto.Changeset{data: %ChurchBands.Accounts.User{}} =
               Accounts.change_user_management(actor, user)
    end

    test "já traz a recusa do próprio papel, antes de salvar" do
      pastor_fixture()
      actor = pastor_fixture()

      changeset = Accounts.change_user_management(actor, actor, %{"global_role" => "member"})

      refute changeset.valid?
      assert errors_on(changeset).global_role != []
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

  describe "accept_invite/2 com o convite mudado depois da tela abrir" do
    test "recusa convite cancelado enquanto o formulário estava aberto" do
      invite = invite_fixture()
      {:ok, _} = Accounts.cancel_invite(invite)

      # `invite` é a struct de antes do cancelamento — é o que a tela de
      # ativação guarda desde a montagem.
      assert {:error, :invalid_invite} = Accounts.accept_invite(invite, @valid_activation)
      assert is_nil(Accounts.get_user_by_email(invite.email))
    end

    test "recusa convite que expirou enquanto o formulário estava aberto" do
      invite = invite_fixture()
      Repo.update!(Ecto.Changeset.change(invite, expires_at: um_dia_atras()))

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

  describe "sessões guardadas no banco" do
    test "abrir uma sessão devolve o token que a encontra de volta" do
      user = member_fixture()

      token = Accounts.generate_user_session_token(user)

      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "duas sessões da mesma pessoa são duas linhas, e uma não sabe da outra" do
      user = member_fixture()

      casa = Accounts.generate_user_session_token(user)
      trabalho = Accounts.generate_user_session_token(user)

      Accounts.delete_user_session_token(casa)

      refute Accounts.get_user_by_session_token(casa)
      assert Accounts.get_user_by_session_token(trabalho).id == user.id
    end

    test "token que nunca existiu não abre sessão nenhuma" do
      member_fixture()

      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end

    test "a sessão vence depois do prazo, e a linha sozinha não basta" do
      user = member_fixture()
      token = Accounts.generate_user_session_token(user)

      vencida =
        DateTime.utc_now()
        |> DateTime.add(-UserToken.session_validity_in_days() - 1, :day)
        |> DateTime.truncate(:second)

      Repo.update_all(from(t in UserToken, where: t.token == ^token),
        set: [inserted_at: vencida]
      )

      refute Accounts.get_user_by_session_token(token)
    end

    test "token de outro contexto não abre sessão, mesmo estando na tabela" do
      user = member_fixture()
      token = :crypto.strong_rand_bytes(32)

      Repo.insert!(%UserToken{token: token, context: "outro", user_id: user.id})

      refute Accounts.get_user_by_session_token(token)
    end

    test "apagar a conta leva as sessões dela junto" do
      user = member_fixture()
      token = Accounts.generate_user_session_token(user)

      Repo.delete!(user)

      refute Accounts.get_user_by_session_token(token)
      assert Repo.all(UserToken) == []
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

  defp um_dia_atras do
    DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
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

  describe "ordem alfabética de list_users/1" do
    # Mesma raiz do que corrige as listas de bandas: sem locale no banco, o
    # byte do "Â" valia mais que o de qualquer letra sem acento e a Ângela ia
    # parar depois do Zeca.
    test "o nome acentuado fica no lugar em que se lê" do
      for nome <- ~w(Zeca André Ângela Bruno) do
        user_fixture(%{name: nome})
      end

      nomes = Enum.map(Accounts.list_users(), & &1.name)

      assert Enum.filter(nomes, &(&1 in ~w(Zeca André Ângela Bruno))) ==
               ~w(André Ângela Bruno Zeca)
    end
  end
end
