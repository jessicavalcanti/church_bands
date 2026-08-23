defmodule ChurchBands.InviteDeliveryTest do
  @moduledoc """
  O que acontece quando o servidor de e-mail está fora do ar.

  Convidar alguém é gravar um registro **e** entregar um link; se só a primeira
  metade acontece, a pessoa nunca recebe nada e quem convidou fica achando que
  recebeu. Estes testes trocam o adapter do `ChurchBands.Mailer` pelo
  `ChurchBands.FailingMailerAdapter` para exercitar essa metade.

  O caso é **síncrono** de propósito: a configuração do mailer é global e uma
  troca dessas valeria também para os testes rodando em paralelo.
  """
  use ChurchBandsWeb.ConnCase, async: false

  import ChurchBands.AccountsFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Accounts

  setup do
    original = Application.get_env(:church_bands, ChurchBands.Mailer)

    Application.put_env(:church_bands, ChurchBands.Mailer,
      adapter: ChurchBands.FailingMailerAdapter
    )

    on_exit(fn -> Application.put_env(:church_bands, ChurchBands.Mailer, original) end)
  end

  describe "Accounts.create_invite/2" do
    test "avisa que a entrega falhou em vez de dar o convite por enviado" do
      leader = worship_leader_fixture()

      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Accounts.create_invite(%{email: "nova@exemplo.com"}, leader)
    end
  end

  describe "Accounts.resend_invite/1" do
    test "avisa que a entrega falhou" do
      leader = worship_leader_fixture()

      invite =
        with_mailer_ok(fn -> invite_fixture(%{invited_by: leader}) end)

      assert {:error, {:delivery_failed, :servidor_de_email_fora_do_ar}} =
               Accounts.resend_invite(invite)
    end
  end

  describe "tela de convites" do
    test "mostra o erro de envio e não deixa o formulário em silêncio", %{conn: conn} do
      leader = worship_leader_fixture()
      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/admin/invites/new")

      html =
        view
        |> form("#invite-form", invite: %{email: "nova@exemplo.com"})
        |> render_submit()

      assert html =~ "Não foi possível enviar o e-mail do convite."
    end

    test "reenviar avisa quando o e-mail não sai", %{conn: conn} do
      leader = worship_leader_fixture()
      invite = with_mailer_ok(fn -> invite_fixture(%{invited_by: leader}) end)

      {:ok, view, _html} = live(log_in_user(conn, leader), ~p"/admin/invites")

      assert view |> element("#resend-invite-#{invite.id}") |> render_click() =~
               "Não foi possível reenviar o convite."
    end
  end

  # A montagem do cenário precisa de um convite que existe; só a ação sob teste
  # é que roda com o servidor de e-mail fora do ar.
  defp with_mailer_ok(fun) do
    falho = Application.get_env(:church_bands, ChurchBands.Mailer)
    Application.put_env(:church_bands, ChurchBands.Mailer, adapter: Swoosh.Adapters.Test)

    try do
      fun.()
    after
      Application.put_env(:church_bands, ChurchBands.Mailer, falho)
    end
  end
end
