defmodule ChurchBandsWeb.ContentSecurityPolicyTest do
  @moduledoc """
  O cabeçalho `content-security-policy` e o nonce que ele autoriza.

  O que mais importa aqui é o nonce **chegar aos dois scripts inline**: um
  nonce que não bate é pior do que não ter CSP, porque o navegador bloqueia o
  script que corrige a tela antes da primeira pintura e a barra lateral volta a
  piscar (#31).
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures

  describe "o cabeçalho" do
    test "acompanha toda resposta HTML", %{conn: conn} do
      conn = get(conn, ~p"/login")

      assert policy(conn) =~ "default-src 'self'"
      assert policy(conn) =~ "frame-ancestors 'none'"
      assert policy(conn) =~ "object-src 'none'"
      assert policy(conn) =~ "font-src 'self' https://fonts.gstatic.com"
    end

    test "sorteia um nonce novo a cada resposta", %{conn: conn} do
      refute nonce(get(conn, ~p"/login")) == nonce(get(conn, ~p"/login"))
    end
  end

  describe "os scripts inline" do
    test "o do tema leva o nonce da resposta", %{conn: conn} do
      conn = get(conn, ~p"/login")

      assert html_response(conn, 200) =~ ~s(<script nonce="#{nonce(conn)}">)
    end

    test "o da barra lateral leva o mesmo nonce, na tela do portal", %{conn: conn} do
      conn = conn |> log_in_user(member_fixture()) |> get(~p"/bands")
      html = html_response(conn, 200)

      # O do tema vem da `conn`; o da barra lateral, da sessão, por dentro da
      # LiveView. São dois caminhos diferentes para o mesmo nonce.
      assert length(Regex.scan(~r/nonce="#{Regex.escape(nonce(conn))}"/, html)) == 2
    end
  end

  describe "o onload do avatar" do
    test "está autorizado pelo hash do que o componente realmente escreve", %{conn: conn} do
      # O hash sai do HTML renderizado, e não de uma cópia do handler no teste:
      # é assim que mudar o componente do SaladUI reprova aqui, em vez de
      # bloquear a foto no navegador sem ninguém perceber.
      user = member_fixture(%{photo_url: "https://exemplo.com/carla.jpg"})
      conn = conn |> log_in_user(user) |> get(~p"/bands")

      [_tag, handler] = Regex.run(~r/onload="([^"]+)"/, html_response(conn, 200))
      hash = :sha256 |> :crypto.hash(handler) |> Base.encode64()

      assert policy(conn) =~ "'unsafe-hashes'"
      assert policy(conn) =~ "'sha256-#{hash}'"
    end
  end

  defp policy(conn) do
    [policy] = get_resp_header(conn, "content-security-policy")
    policy
  end

  defp nonce(conn) do
    [_diretiva, nonce] = Regex.run(~r/'nonce-([^']+)'/, policy(conn))
    nonce
  end
end
