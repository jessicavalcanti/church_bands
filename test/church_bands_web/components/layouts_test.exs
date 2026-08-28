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

  describe "o sino da moldura" do
    # Sem não lidas o que some é o **contador**, não o sino: esconder o sino de
    # quem não tem nada esconderia o caminho para a lista de quem quer olhar o
    # histórico.
    test "sem não lidas, o sino aparece sem número" do
      html = render_component(&portal_sem_usuario/1, %{unread: 0})

      assert [sino] = seletor(html, "#notifications-bell")
      assert LazyHTML.attribute(sino, "href") == ["/notifications"]
      assert seletor(html, "#unread-notifications") == []
    end

    test "com não lidas, o sino carrega o número" do
      html = render_component(&portal_sem_usuario/1, %{unread: 3})

      assert [contador] = seletor(html, "#unread-notifications")
      assert LazyHTML.text(contador) =~ "3"
    end
  end

  describe "flash_group/1" do
    test "a mensagem de flash vai para o toaster, e não para um cartão na página" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{"info" => "Instrumento salvo."}})

      # Quem desenha a mensagem é o JavaScript do toast, a partir da ponte —
      # na página ela chega como dado, não como cartão pronto.
      assert [ponte] = seletor(html, "#toaster-flash-bridge")
      assert [entradas] = LazyHTML.attribute(ponte, "data-entries")
      assert entradas =~ "Instrumento salvo."
      assert entradas =~ ~s("kind":"info")

      assert seletor(html, "#flash-info") == []
    end

    test "monta um toaster só, no canto de cima à direita" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{}})

      assert [toaster] = seletor(html, ~s([data-component="toast"]))
      assert LazyHTML.attribute(toaster, "id") == ["toaster"]
      assert [opcoes] = LazyHTML.attribute(toaster, "data-options")
      assert opcoes =~ ~s("position":"top-right")
    end

    test "os dois avisos de conexão não passam pelo toaster" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{}})

      for id <- ["#client-error", "#server-error"] do
        assert [cartao] = seletor(html, id)
        assert LazyHTML.attribute(cartao, "role") == ["alert"]
        assert LazyHTML.attribute(cartao, "phx-click") |> List.first() =~ "lv:clear-flash"
      end
    end
  end

  describe "flash/1" do
    test "traz o x de fechar, e ele fecha o mesmo aviso que o cartão" do
      html =
        render_component(&Layouts.flash/1, %{
          id: "client-error",
          kind: :error,
          inner_block: inner_block("Tentando reconectar")
        })

      assert [_botao] = seletor(html, ~s(#client-error button[aria-label="Fechar aviso"]))

      # O botão não tem caminho próprio: o clique sobe para o cartão, que é
      # quem limpa o flash no servidor.
      assert [cartao] = seletor(html, "#client-error")
      assert LazyHTML.attribute(cartao, "phx-click") |> List.first() =~ "lv:clear-flash"
    end

    test "sem mensagem, não desenha aviso nenhum" do
      html = render_component(&Layouts.flash/1, %{kind: :info, flash: %{}})

      assert seletor(html, "#flash-info") == []
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
    assigns = assign_new(assigns, :unread, fn -> 0 end)

    ~H"""
    <Layouts.app flash={%{}} sidebar_state="expanded" unread={@unread}>
      <p id="conteudo">Conteúdo da tela</p>
    </Layouts.app>
    """
  end
end
