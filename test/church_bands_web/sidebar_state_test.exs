defmodule ChurchBandsWeb.SidebarStateTest do
  @moduledoc """
  O plug que traz do cookie a escolha de recolher a barra lateral.

  O efeito visível — a barra chegar recolhida no HTML — é exercido em
  `ChurchBandsWeb.PortalTest`. O que só aparece olhando o plug de perto é
  quando ele **escreve na sessão**: escrever a cada requisição faria o cookie
  de sessão voltar em toda resposta, que é justamente o custo que este desenho
  veio tirar.
  """
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures

  alias ChurchBandsWeb.SidebarState

  defp run(conn), do: SidebarState.call(conn, SidebarState.init([]))

  defp com_sessao(conn), do: Phoenix.ConnTest.init_test_session(conn, %{})

  test "o cookie recolhido vira o estado da barra", %{conn: conn} do
    conn = conn |> com_sessao() |> put_req_cookie("sidebar_state", "collapsed") |> run()

    assert conn.assigns.sidebar_state == "collapsed"
    assert get_session(conn, :sidebar_state) == "collapsed"
  end

  test "sem cookie, a barra é a expandida do componente", %{conn: conn} do
    conn = conn |> com_sessao() |> run()

    assert conn.assigns.sidebar_state == "expanded"
  end

  test "cookie com valor desconhecido também é barra expandida", %{conn: conn} do
    conn = conn |> com_sessao() |> put_req_cookie("sidebar_state", "recolhidinha") |> run()

    assert conn.assigns.sidebar_state == "expanded"
  end

  # Numa requisição de verdade: a primeira resposta reescreve o cookie de
  # sessão porque a escolha mudou; a segunda, com tudo igual, não devolve
  # `set-cookie` nenhum. É esse o ganho de comparar antes de gravar — o nonce
  # da CSP, que mudava a cada resposta, fazia o cookie voltar sempre.
  test "a sessão só é reescrita quando a escolha muda", %{conn: conn} do
    conn = conn |> log_in_user(member_fixture()) |> put_req_cookie("sidebar_state", "collapsed")

    primeira = get(conn, ~p"/bands")
    assert reescreveu_a_sessao?(primeira)

    segunda = primeira |> Phoenix.ConnTest.recycle() |> get(~p"/bands")
    refute reescreveu_a_sessao?(segunda)
  end

  defp reescreveu_a_sessao?(conn), do: Map.has_key?(conn.resp_cookies, "_church_bands_key")
end
