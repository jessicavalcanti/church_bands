defmodule ChurchBandsWeb.InviteLive.ActivateTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Repo

  @valid %{
    "name" => "Nova Pessoa",
    "password" => "senha123456",
    "password_confirmation" => "senha123456"
  }

  describe "link de convite válido" do
    setup do
      %{invite: invite_fixture()}
    end

    test "mostra o formulário de ativação com o e-mail convidado", %{conn: conn, invite: invite} do
      {:ok, view, html} = live(conn, ~p"/invites/#{invite.token}/activate")

      assert has_element?(view, "#activation-form")
      assert has_element?(view, "#activate-account-button")
      assert html =~ invite.email
      refute has_element?(view, "#invalid-invite")
    end

    test "ativa a conta e leva para o login", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      view |> form("#activation-form", user: @valid) |> render_submit()

      assert {to, flash} = assert_redirect(view)
      assert to == ~p"/login?#{[email: invite.email]}"
      assert flash["info"] =~ "Conta ativada"

      user = Accounts.get_user_by_email(invite.email)
      assert user.name == "Nova Pessoa"
      assert user.confirmed_at
      assert Repo.get!(Invite, invite.id).status == :accepted
    end

    test "a conta ativada consegue logar em seguida", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")
      view |> form("#activation-form", user: @valid) |> render_submit()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => invite.email, "password" => "senha123456"}
        })

      assert get_session(conn, :user_id) == Accounts.get_user_by_email(invite.email).id
    end

    test "recusa senha fraca sem criar a conta", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      html =
        view
        |> form("#activation-form",
          user: %{"name" => "Nova Pessoa", "password" => "abc", "password_confirmation" => "abc"}
        )
        |> render_submit()

      assert html =~ "precisa ter ao menos 8 caracteres"
      refute Accounts.get_user_by_email(invite.email)
      assert Repo.get!(Invite, invite.id).status == :pending
    end

    test "recusa confirmação de senha diferente", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      html =
        view
        |> form("#activation-form", user: %{@valid | "password_confirmation" => "outra123456"})
        |> render_submit()

      assert html =~ "não confere com a senha"
      refute Accounts.get_user_by_email(invite.email)
    end

    test "valida enquanto a pessoa digita", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      html =
        view
        |> form("#activation-form", user: %{"name" => "", "password" => "abc"})
        |> render_change()

      assert html =~ "não pode ficar em branco"
    end

    test "o e-mail da conta vem do convite, não do formulário", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      view
      |> render_submit("save", %{"user" => Map.put(@valid, "email", "invasor@exemplo.com")})

      assert Accounts.get_user_by_email(invite.email)
      refute Accounts.get_user_by_email("invasor@exemplo.com")
    end
  end

  describe "convite que deixa de valer com o formulário aberto" do
    test "cancelado entre abrir e enviar cai na tela de link inválido", %{conn: conn} do
      invite = invite_fixture()
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      {:ok, _} = Accounts.cancel_invite(invite)

      view |> form("#activation-form", user: @valid) |> render_submit()

      assert has_element?(view, "#invalid-invite")
      refute has_element?(view, "#activation-form")
      assert is_nil(Accounts.get_user_by_email(invite.email))
    end

    test "e-mail que ganhou conta nesse meio-tempo avisa para usar o login", %{conn: conn} do
      invite = invite_fixture()
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")

      user_fixture(%{email: invite.email})

      html = view |> form("#activation-form", user: @valid) |> render_submit()

      assert html =~ "Este e-mail já possui uma conta"
      assert Repo.get!(Invite, invite.id).status == :pending
    end
  end

  describe "link de convite inválido" do
    test "token desconhecido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invites/token-que-nao-existe/activate")

      assert has_element?(view, "#invalid-invite")
      refute has_element?(view, "#activation-form")
    end

    test "convite cancelado", %{conn: conn} do
      {:ok, cancelled} = Accounts.cancel_invite(invite_fixture())

      {:ok, view, _html} = live(conn, ~p"/invites/#{cancelled.token}/activate")

      assert has_element?(view, "#invalid-invite")
    end

    test "convite expirado", %{conn: conn} do
      invite = invite_fixture()
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      expired = Repo.update!(Ecto.Changeset.change(invite, expires_at: past))

      {:ok, view, _html} = live(conn, ~p"/invites/#{expired.token}/activate")

      assert has_element?(view, "#invalid-invite")
    end

    test "convite já aceito não pode ser usado de novo", %{conn: conn} do
      invite = invite_fixture()
      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")
      view |> form("#activation-form", user: @valid) |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/invites/#{invite.token}/activate")
      assert has_element?(view, "#invalid-invite")
    end
  end
end
