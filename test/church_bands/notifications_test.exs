defmodule ChurchBands.NotificationsTest do
  @moduledoc """
  A central de notificações vista do contexto (US 4.5).

  O que se prova aqui é o recorte por dono, que é o ponto do módulo: toda
  função recebe a pessoa e filtra por ela **dentro** da consulta, e é isso que
  faz a notificação de terceiros e o id inventado darem na mesma recusa.
  """
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.NotificationsFixtures

  alias ChurchBands.Notifications
  alias ChurchBands.Notifications.Notification

  describe "notify/3" do
    test "grava a notificação da pessoa, não lida" do
      user = member_fixture()

      assert {:ok, notification} =
               Notifications.notify(user, :swap_requested, %{
                 title: "Pedido de troca de escala",
                 body: "Elias pediu troca com você.",
                 path: "/swaps"
               })

      assert notification.user_id == user.id
      assert notification.kind == :swap_requested
      assert notification.title == "Pedido de troca de escala"
      assert notification.body == "Elias pediu troca com você."
      assert notification.path == "/swaps"
      assert is_nil(notification.read_at)
    end

    test "notificação sem texto é recusada" do
      user = member_fixture()

      assert {:error, changeset} =
               Notifications.notify(user, :swap_accepted, %{title: "", body: "", path: ""})

      assert %{title: ["can't be blank"], body: ["can't be blank"], path: ["can't be blank"]} =
               errors_on(changeset)
    end
  end

  describe "list_for_user/1" do
    test "traz as da pessoa, da mais recente para a mais antiga" do
      user = member_fixture()
      agora = ChurchBands.LocalTime.now()

      antiga =
        notification_fixture(user, title: "Antiga", inserted_at: DateTime.add(agora, -2, :hour))

      recente = notification_fixture(user, title: "Recente", inserted_at: agora)

      assert [primeira, segunda] = Notifications.list_for_user(user)
      assert primeira.id == recente.id
      assert segunda.id == antiga.id
    end

    test "não traz as de outra pessoa" do
      user = member_fixture()
      outra = member_fixture()
      minha = notification_fixture(user)
      notification_fixture(outra)

      assert [encontrada] = Notifications.list_for_user(user)
      assert encontrada.id == minha.id
    end

    test "quem não tem notificação nenhuma recebe lista vazia" do
      assert Notifications.list_for_user(member_fixture()) == []
    end

    test "a lista inteira sai numa consulta só" do
      user = member_fixture()
      for _ <- 1..3, do: notification_fixture(user)

      assert_queries(1, fn -> Notifications.list_for_user(user) end)
    end
  end

  describe "unread_count/1" do
    test "conta só as não lidas da pessoa" do
      user = member_fixture()
      outra = member_fixture()
      notification_fixture(user)
      notification_fixture(user)
      notification_fixture(user, read_at: ChurchBands.LocalTime.now())
      notification_fixture(outra)

      assert Notifications.unread_count(user) == 2
    end

    test "quem leu tudo tem zero" do
      user = member_fixture()
      notification_fixture(user, read_at: ChurchBands.LocalTime.now())

      assert Notifications.unread_count(user) == 0
    end

    # A vitrine pública de `/` passa por aqui em toda visita: perguntar ao banco
    # o que não depende do banco seria cobrar de quem nem entrou.
    test "visitante tem zero, e sem consulta nenhuma" do
      assert assert_queries(0, fn -> Notifications.unread_count(nil) end) == 0
    end
  end

  describe "get_for_user/2" do
    test "acha a notificação da própria pessoa" do
      user = member_fixture()
      notification = notification_fixture(user)

      assert %Notification{} = encontrada = Notifications.get_for_user(user, notification.id)
      assert encontrada.id == notification.id
    end

    test "o id vindo da tela como texto também acha" do
      user = member_fixture()
      notification = notification_fixture(user)

      assert %Notification{} = Notifications.get_for_user(user, to_string(notification.id))
    end

    # As duas recusas são a mesma de propósito: dizer <q>existe, mas não é
    # sua</q> já contaria algo sobre a vida de terceiros.
    test "a notificação de outra pessoa não é encontrada" do
      user = member_fixture()
      alheia = notification_fixture(member_fixture())

      assert Notifications.get_for_user(user, alheia.id) == nil
    end

    test "id inventado não é encontrado" do
      assert Notifications.get_for_user(member_fixture(), 999_999) == nil
    end

    test "id que nem número é não é encontrado, e não estoura" do
      assert Notifications.get_for_user(member_fixture(), "abc") == nil
    end
  end

  describe "mark_read/2" do
    test "a não lida da própria pessoa passa a ter data de leitura" do
      user = member_fixture()
      notification = notification_fixture(user)

      lida = Notifications.mark_read(user, notification)

      assert lida.read_at
      assert Repo.get!(Notification, notification.id).read_at
    end

    # Regra 14: marcar como lido o que já está lido não muda nada e não é erro.
    test "a que já estava lida volta intacta, com a data original" do
      user = member_fixture()
      antes = DateTime.add(ChurchBands.LocalTime.now(), -1, :hour)
      notification = notification_fixture(user, read_at: antes)

      assert Notifications.mark_read(user, notification).read_at == notification.read_at
      assert Repo.get!(Notification, notification.id).read_at == notification.read_at
    end

    # A reconferência no servidor de quem chegou aqui por fora da tela: o
    # recorte de `get_for_user/2` já barra o caminho normal, e este é o outro.
    test "marcar como lida a notificação de outra pessoa não muda nada" do
      user = member_fixture()
      alheia = notification_fixture(member_fixture())

      assert Notifications.mark_read(user, alheia) == alheia
      assert is_nil(Repo.get!(Notification, alheia.id).read_at)
    end
  end

  describe "mark_all_read/1" do
    test "zera as não lidas da pessoa de uma vez" do
      user = member_fixture()
      notification_fixture(user)
      notification_fixture(user)

      assert Notifications.mark_all_read(user) == :ok
      assert Notifications.unread_count(user) == 0
    end

    test "não toca nas de outra pessoa" do
      user = member_fixture()
      outra = member_fixture()
      notification_fixture(user)
      notification_fixture(outra)

      Notifications.mark_all_read(user)

      assert Notifications.unread_count(outra) == 1
    end

    test "quem não tem nada por ler continua sem nada por ler" do
      user = member_fixture()

      assert Notifications.mark_all_read(user) == :ok
      assert Notifications.unread_count(user) == 0
    end

    test "a data de leitura e a de alteração acompanham" do
      user = member_fixture()
      notification = notification_fixture(user)

      Notifications.mark_all_read(user)
      lida = Repo.get!(Notification, notification.id)

      assert lida.read_at
      assert lida.updated_at == lida.read_at
    end
  end

  # Notificação não se apaga, mas ela morre com a conta: é o
  # `on_delete: :delete_all` da chave, e não uma limpeza escrita à mão.
  test "excluir a pessoa apaga as notificações dela" do
    user = member_fixture()
    outra = member_fixture()
    notification_fixture(user)
    sobrevivente = notification_fixture(outra)

    Repo.delete!(user)

    assert Repo.all(Notification) |> Enum.map(& &1.id) == [sobrevivente.id]
  end
end
