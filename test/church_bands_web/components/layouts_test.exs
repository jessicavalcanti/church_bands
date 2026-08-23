defmodule ChurchBandsWeb.LayoutsTest do
  @moduledoc """
  As duas molduras, montadas direto como componente.

  O portal em uso é exercido pelas telas em `ChurchBandsWeb.PortalTest`; o que
  só aparece aqui é a moldura montada **sem usuário**, que é o estado em que
  ela fica antes de o `current_user` chegar ao socket.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ChurchBandsWeb.Layouts

  describe "app/1 sem usuário" do
    test "não oferece item de menu nenhum" do
      html = render_component(&portal_sem_usuario/1, %{})

      refute html =~ ~s(id="home-link")
      refute html =~ ~s(id="bands-link")
      refute html =~ ~s(id="users-link")
      refute html =~ ~s(id="invites-link")
    end

    test "ainda assim desenha a moldura e o conteúdo da tela" do
      html = render_component(&portal_sem_usuario/1, %{})

      assert html =~ ~s(id="app-sidebar")
      assert html =~ "Conteúdo da tela"
    end
  end

  defp portal_sem_usuario(assigns) do
    ~H"""
    <Layouts.app flash={%{}} csp_nonce="nonce-de-teste">
      <p id="conteudo">Conteúdo da tela</p>
    </Layouts.app>
    """
  end
end
