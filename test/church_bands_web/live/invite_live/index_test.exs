defmodule ChurchBandsWeb.InviteLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Repo

  describe "autorização de acesso" do
    test "Líder de Louvor acessa a tela de convites", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/admin/invites")
      assert has_element?(view, "#new-invite-button")
    end

    test "Pastor acessa a tela de convites", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/admin/invites")
      assert has_element?(view, "#new-invite-button")
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/invites")
      assert flash["error"] =~ "não tem permissão"
    end

    test "visitante não autenticado tem o acesso negado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/admin/invites")
      assert flash["error"] =~ "precisa entrar"
    end
  end

  describe "envio de convite" do
    setup %{conn: conn} do
      leader = worship_leader_fixture()
      %{conn: log_in_user(conn, leader), leader: leader}
    end

    test "registra o convite como pendente ao informar um e-mail válido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      assert has_element?(view, "#invites-empty")

      view |> element("#new-invite-button") |> render_click()
      assert has_element?(view, "#invite-form")

      view
      |> form("#invite-form", invite: %{email: "nova@exemplo.com"})
      |> render_submit()

      assert [invite] = Accounts.list_invites()
      assert invite.email == "nova@exemplo.com"
      assert invite.status == :pending

      assert has_element?(view, "#invites")
      assert render(view) =~ "nova@exemplo.com"
      assert render(view) =~ "Pendente"
    end

    test "aponta o e-mail inválido enquanto a pessoa digita", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites/new")

      html =
        view
        |> form("#invite-form", invite: %{email: "sem-arroba"})
        |> render_change()

      assert html =~ "precisa ser um e-mail válido"
      assert Accounts.list_invites() == []
    end

    test "exibe erro ao convidar e-mail que já possui conta", %{conn: conn} do
      existing = member_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/invites/new")

      html =
        view
        |> form("#invite-form", invite: %{email: existing.email})
        |> render_submit()

      assert html =~ "já possui uma conta no sistema"
      assert Accounts.list_invites() == []
    end

    test "exibe erro ao convidar e-mail com convite pendente", %{conn: conn, leader: leader} do
      invite = invite_fixture(%{invited_by: leader})
      {:ok, view, _html} = live(conn, ~p"/admin/invites/new")

      html =
        view
        |> form("#invite-form", invite: %{email: invite.email})
        |> render_submit()

      assert html =~ "já possui um convite pendente"
    end

    test "exibe erro de formato ao informar e-mail inválido", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites/new")

      html =
        view
        |> form("#invite-form", invite: %{email: "sem-arroba"})
        |> render_submit()

      assert html =~ "precisa ser um e-mail válido"
    end
  end

  describe "reenvio e cancelamento" do
    setup %{conn: conn} do
      leader = worship_leader_fixture()
      invite = invite_fixture(%{invited_by: leader})
      %{conn: log_in_user(conn, leader), leader: leader, invite: invite}
    end

    test "reenviar gera um novo token", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      view |> element("#resend-invite-#{invite.id}") |> render_click()

      assert [resent] = Accounts.list_invites()
      assert resent.token != invite.token
      assert resent.status == :pending
    end

    test "cancelar marca o convite como cancelado", %{conn: conn, invite: invite} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      view |> element("#cancel-invite-#{invite.id}") |> render_click()

      assert [cancelled] = Accounts.list_invites()
      assert cancelled.status == :cancelled
      assert render(view) =~ "Cancelado"
    end

    test "convite cancelado não oferece mais a ação de cancelar", %{conn: conn, invite: invite} do
      {:ok, _} = Accounts.cancel_invite(invite)
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      refute has_element?(view, "#cancel-invite-#{invite.id}")
      assert has_element?(view, "#resend-invite-#{invite.id}")
    end

    test "convite aceito não oferece nenhuma das duas ações", %{conn: conn, invite: invite} do
      aceitar(invite)
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      refute has_element?(view, "#resend-invite-#{invite.id}")
      refute has_element?(view, "#cancel-invite-#{invite.id}")
    end

    test "reenviar um convite já aceito é recusado, mesmo forçando o evento", %{
      conn: conn,
      invite: invite
    } do
      aceitar(invite)
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      html = render_click(view, "resend", %{"id" => to_string(invite.id)})

      assert html =~ "já foi aceito e não pode ser reenviado"
      assert Repo.get!(Invite, invite.id).token == invite.token
    end

    test "cancelar um convite já aceito é recusado, mesmo forçando o evento", %{
      conn: conn,
      invite: invite
    } do
      aceitar(invite)
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      html = render_click(view, "cancel", %{"id" => to_string(invite.id)})

      assert html =~ "já foi aceito e não pode ser cancelado"
      assert Repo.get!(Invite, invite.id).status == :accepted
    end

    test "reenviar um convite que não existe mais avisa em vez de estourar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      assert render_click(view, "resend", %{"id" => "0"}) =~
               "Não foi possível reenviar o convite."
    end

    test "cancelar um convite que não existe mais avisa em vez de estourar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/invites")

      assert render_click(view, "cancel", %{"id" => "0"}) =~
               "Não foi possível cancelar o convite."
    end
  end

  describe "status na listagem" do
    setup %{conn: conn} do
      leader = worship_leader_fixture()
      %{conn: log_in_user(conn, leader), leader: leader}
    end

    test "mostra o status de cada convite por extenso", %{conn: conn, leader: leader} do
      pendente = invite_fixture(%{invited_by: leader})
      aceito = invite_fixture(%{invited_by: leader}) |> aceitar()
      cancelado = invite_fixture(%{invited_by: leader})
      {:ok, _} = Accounts.cancel_invite(cancelado)

      invite_fixture(%{invited_by: leader})
      |> Ecto.Changeset.change(expires_at: ontem())
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/invites")
      html = render(view)

      assert html =~ "Pendente"
      assert html =~ "Aceito"
      assert html =~ "Expirado"
      assert html =~ "Cancelado"
      assert html =~ pendente.email
      assert html =~ aceito.email
    end
  end

  defp aceitar(invite) do
    invite
    |> Ecto.Changeset.change(status: :accepted)
    |> Repo.update!()
  end

  defp ontem do
    DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
  end
end
