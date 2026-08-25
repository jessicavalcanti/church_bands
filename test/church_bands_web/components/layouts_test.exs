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

  describe "flash/1" do
    test "traz o x de fechar, e ele fecha o mesmo aviso que o cartão" do
      html = render_component(&Layouts.flash/1, %{kind: :info, flash: %{"info" => "Salvo."}})

      assert [_botao] = seletor(html, ~s(#flash-info button[aria-label="Fechar aviso"]))

      # O botão não tem caminho próprio: o clique sobe para o cartão, que é
      # quem limpa o flash no servidor.
      assert [cartao] = seletor(html, "#flash-info")
      assert LazyHTML.attribute(cartao, "phx-click") |> List.first() =~ "lv:clear-flash"
    end

    test "arma o relógio que faz o aviso sumir sozinho" do
      html = render_component(&Layouts.flash/1, %{kind: :info, flash: %{"info" => "Salvo."}})

      assert [cartao] = seletor(html, "#flash-info")
      assert LazyHTML.attribute(cartao, "phx-hook") == ["FlashAutoDismiss"]
      assert LazyHTML.attribute(cartao, "data-duration") == ["4000"]
    end

    test "sem duração, o aviso fica na tela até alguém fechá-lo" do
      html =
        render_component(&Layouts.flash/1, %{
          id: "client-error",
          kind: :error,
          duration: nil,
          inner_block: inner_block("Tentando reconectar")
        })

      assert [cartao] = seletor(html, "#client-error")
      assert LazyHTML.attribute(cartao, "phx-hook") == []
      assert LazyHTML.attribute(cartao, "data-duration") == []
      assert [_botao] = seletor(html, ~s(#client-error button[aria-label="Fechar aviso"]))
    end

    test "sem mensagem, não desenha aviso nenhum" do
      html = render_component(&Layouts.flash/1, %{kind: :info, flash: %{}})

      assert seletor(html, "#flash-info") == []
    end
  end

  describe "flash_group/1" do
    test "os dois avisos de conexão não somem sozinhos" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{}})

      for id <- ["#client-error", "#server-error"] do
        assert [cartao] = seletor(html, id)
        assert LazyHTML.attribute(cartao, "phx-hook") == []
      end
    end
  end

  defp seletor(html, seletor) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(seletor)
    |> Enum.to_list()
  end

  defp inner_block(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end

  defp portal_sem_usuario(assigns) do
    ~H"""
    <Layouts.app flash={%{}} sidebar_state="expanded">
      <p id="conteudo">Conteúdo da tela</p>
    </Layouts.app>
    """
  end
end
