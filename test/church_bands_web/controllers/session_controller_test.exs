defmodule ChurchBandsWeb.SessionControllerTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures

  @limit Application.compile_env!(:church_bands, ChurchBands.RateLimit)[:login][:limit]

  describe "POST /login" do
    test "abre a sessão com e-mail e senha corretos", %{conn: conn} do
      user = member_fixture(%{password: "senha123456"})

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "senha123456"}
        })

      assert get_session(conn, :user_id) == user.id
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ user.name
    end

    test "dá acesso às telas restritas quando o perfil permite", %{conn: conn} do
      leader = worship_leader_fixture(%{password: "senha123456"})

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => leader.email, "password" => "senha123456"}
        })

      assert html_response(get(recycle(conn), ~p"/admin/invites"), 200) =~ "Convites"
    end

    test "recusa senha incorreta e devolve ao login", %{conn: conn} do
      user = member_fixture(%{password: "senha123456"})

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "senha-errada-1"}
        })

      refute get_session(conn, :user_id)
      assert redirected_to(conn) == ~p"/login?#{[email: user.email]}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "E-mail ou senha incorretos"
    end

    test "recusa e-mail sem conta", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "ninguem@exemplo.com", "password" => "senha123456"}
        })

      refute get_session(conn, :user_id)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "E-mail ou senha incorretos"
    end

    test "recusa novas tentativas depois de muitas seguidas do mesmo lugar", %{conn: conn} do
      user = member_fixture(%{password: "senha123456"})
      errada = %{"user" => %{"email" => user.email, "password" => "senha-errada-1"}}

      for _ <- 1..@limit, do: post(conn, ~p"/login", errada)

      # A senha certa, e mesmo assim recusada: é o que faz a força bruta parar
      # de valer a pena.
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "senha123456"}
        })

      refute get_session(conn, :user_id)
      assert redirected_to(conn) == ~p"/login?#{[email: user.email]}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Muitas tentativas"
    end
  end

  describe "DELETE /logout" do
    test "encerra a sessão", %{conn: conn} do
      conn =
        conn
        |> log_in_user(member_fixture())
        |> delete(~p"/logout")

      refute get_session(conn, :user_id)
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "saiu do sistema"
    end
  end
end
