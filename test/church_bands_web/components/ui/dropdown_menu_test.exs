defmodule ChurchBandsWeb.Components.UI.DropdownMenuTest do
  @moduledoc """
  As peças do menu suspenso do SaladUI.

  O menu do rodapé da barra lateral é exercido pelas telas em
  `ChurchBandsWeb.PortalTest`; aqui ficam as peças isoladas, incluindo as que a
  moldura de hoje ainda não usa. O que cada uma marca no HTML (`data-part`,
  `data-state`, `data-event-mappings`) é o contrato com o hook JavaScript do
  SaladUI, que não roda em teste — se um `data-part` mudar de nome, o menu para
  de abrir no navegador sem nenhum erro no servidor.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.DropdownMenu
  import Phoenix.Component
  import Phoenix.LiveViewTest

  describe "dropdown_menu_trigger/1" do
    test "por padrão é um <button type=\"button\"> " do
      html = render_component(&dropdown_menu_trigger/1, %{inner_block: bloco("Abrir")})

      assert html =~ ~s(<button)
      assert html =~ ~s(type="button")
      assert html =~ ~s(data-part="trigger")
    end

    test "com uma tag HTML em as vira aquele elemento, alcançável por teclado" do
      html =
        render_component(&dropdown_menu_trigger/1, %{as: "span", inner_block: bloco("Abrir")})

      assert html =~ "<span"
      assert html =~ ~s(tabindex="0")
      assert html =~ ~s(data-part="trigger")
    end

    test "com um componente em as continua sendo um botão para o navegador" do
      html =
        render_component(&dropdown_menu_trigger/1, %{
          as: &moldura/1,
          inner_block: bloco("Abrir")
        })

      assert html =~ ~s(id="moldura")
      assert html =~ ~s(type="button")
    end
  end

  describe "dropdown_menu_group/1" do
    test "agrupa itens relacionados para quem usa leitor de tela" do
      html = render_component(&dropdown_menu_group/1, %{inner_block: bloco("Perfil")})

      assert html =~ ~s(role="group")
      assert html =~ ~s(data-part="group")
      assert html =~ "Perfil"
    end
  end

  describe "dropdown_menu_item/1" do
    test "é um item selecionável, com o valor que volta no evento" do
      html =
        render_component(&dropdown_menu_item/1, %{value: "sair", inner_block: bloco("Sair")})

      assert html =~ ~s(data-part="item")
      assert html =~ ~s(data-value="sair")
      assert html =~ ~s(tabindex="0")
    end

    test "item desabilitado sai da ordem de tabulação" do
      html =
        render_component(&dropdown_menu_item/1, %{disabled: true, inner_block: bloco("Sair")})

      assert html =~ ~s(tabindex="-1")
      assert html =~ ~s(data-disabled)
    end

    test "a variante destrutiva é a única que usa o vermelho" do
      html =
        render_component(&dropdown_menu_item/1, %{
          variant: "destructive",
          inner_block: bloco("Excluir")
        })

      assert html =~ "text-destructive"
    end

    test "o manipulador de on-select vai para o mapa de eventos do hook" do
      html =
        render_component(&dropdown_menu_item/1, %{
          "on-select": "escolheu",
          inner_block: bloco("Sair")
        })

      assert html =~ ~s(data-event-mappings)
      assert html =~ "select"
      assert html =~ "escolheu"
    end
  end

  describe "dropdown_menu_checkbox_item/1" do
    test "desmarcado esconde o sinal de conferido" do
      html =
        render_component(&dropdown_menu_checkbox_item/1, %{inner_block: bloco("Notificações")})

      assert html =~ ~s(data-part="checkbox-item")
      assert html =~ ~s(data-state="unchecked")
      assert html =~ "hidden"
    end

    test "marcado mostra o sinal de conferido" do
      html =
        render_component(&dropdown_menu_checkbox_item/1, %{
          checked: true,
          value: "notificacoes",
          inner_block: bloco("Notificações")
        })

      assert html =~ ~s(data-state="checked")
      assert html =~ ~s(data-checked)
      assert html =~ ~s(data-value="notificacoes")
    end

    test "desabilitado sai da ordem de tabulação" do
      html =
        render_component(&dropdown_menu_checkbox_item/1, %{
          disabled: true,
          inner_block: bloco("Notificações")
        })

      assert html =~ ~s(tabindex="-1")
    end
  end

  describe "dropdown_menu_shortcut/1" do
    test "mostra o atalho de teclado ao lado do item" do
      html = render_component(&dropdown_menu_shortcut/1, %{inner_block: bloco("⌘S")})

      assert html =~ ~s(data-part="shortcut")
      assert html =~ "⌘S"
    end
  end

  # Um componente qualquer no lugar do gatilho: o que interessa é que o
  # `dropdown_menu_trigger/1` lhe entregue `type="button"` mesmo assim.
  defp moldura(assigns) do
    ~H"""
    <button id="moldura" type={@type}>{render_slot(@inner_block)}</button>
    """
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
