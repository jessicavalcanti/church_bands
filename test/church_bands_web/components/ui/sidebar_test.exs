defmodule ChurchBandsWeb.Components.UI.SidebarTest do
  @moduledoc """
  As peças da barra lateral do SaladUI.

  A barra montada pelo portal é exercida pelas telas em
  `ChurchBandsWeb.PortalTest`; aqui ficam as peças isoladas, incluindo as que a
  moldura de hoje ainda não usa. São componentes do projeto — foram copiados
  para `lib/church_bands_web/components/ui/` e podem ser editados —, então o
  que cada um marca no HTML (`data-sidebar`, `data-active`, `data-size`) é
  contrato de quem escreve CSS e de quem escreve teste.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Sidebar
  import Phoenix.LiveViewTest

  describe "sidebar/1 com collapsible=\"none\"" do
    test "desenha a barra fixa, sem o invólucro que recolhe" do
      html =
        render_component(&sidebar/1, %{
          id: "barra-fixa",
          collapsible: "none",
          inner_block: bloco("Conteúdo da barra")
        })

      assert html =~ "Conteúdo da barra"
      assert html =~ ~s(data-variant="sidebar")
      refute html =~ ~s(data-collapsible)
    end
  end

  describe "sidebar_rail/1" do
    test "é o punho de arrastar, escondido de quem navega por teclado" do
      html = render_component(&sidebar_rail/1, %{})

      assert html =~ ~s(data-sidebar="rail")
      assert html =~ ~s(aria-label="Toggle Sidebar")
      assert html =~ ~s(tabindex="-1")
    end
  end

  describe "sidebar_input/1" do
    test "é um campo de busca marcado como parte da barra" do
      html = render_component(&sidebar_input/1, %{placeholder: "Buscar"})

      assert html =~ ~s(data-sidebar="input")
      assert html =~ ~s(placeholder="Buscar")
    end
  end

  describe "sidebar_separator/1" do
    test "é um separador marcado como parte da barra" do
      html = render_component(&sidebar_separator/1, %{})

      assert html =~ ~s(data-sidebar="separator")
    end
  end

  describe "sidebar_group_label/1" do
    test "rotula um grupo de itens" do
      html =
        render_component(&sidebar_group_label/1, %{inner_block: bloco("Administração")})

      assert html =~ "Administração"
      assert html =~ ~s(data-sidebar="group-label")
    end

    test "aceita outra tag pelo atributo as" do
      html =
        render_component(&sidebar_group_label/1, %{
          as: "h2",
          inner_block: bloco("Administração")
        })

      assert html =~ "<h2"
      assert html =~ "Administração"
    end
  end

  describe "sidebar_group_action/1" do
    test "é o botão de ação que fica no canto do grupo" do
      html = render_component(&sidebar_group_action/1, %{inner_block: bloco("+")})

      assert html =~ ~s(data-sidebar="group-action")
      assert html =~ "<button"
    end
  end

  describe "sidebar_menu_button/1" do
    test "sem rota vira um <button>, e não um link" do
      html = render_component(&sidebar_menu_button/1, %{inner_block: bloco("Recolher")})

      assert html =~ "<button"
      assert html =~ ~s(data-sidebar="menu-button")
      assert html =~ ~s(data-active="false")
      refute html =~ "href="
    end

    test "com navigate vira um <.link> de LiveView" do
      html =
        render_component(&sidebar_menu_button/1, %{
          navigate: "/bands",
          is_active: true,
          inner_block: bloco("Bandas")
        })

      assert html =~ ~s(href="/bands")
      assert html =~ ~s(data-phx-link="redirect")
      assert html =~ ~s(data-active="true")
    end

    test "o tamanho escolhido aparece no data-size" do
      html =
        render_component(&sidebar_menu_button/1, %{size: "lg", inner_block: bloco("Bandas")})

      assert html =~ ~s(data-size="lg")
    end

    test "com tooltip o botão é embrulhado pela dica" do
      html =
        render_component(&sidebar_menu_button/1, %{
          tooltip: "Ir para bandas",
          inner_block: bloco("Bandas")
        })

      assert html =~ ~s(data-component="tooltip")
      assert html =~ "Ir para bandas"
    end

    # Quem decide se a dica aparece é o CSS, e não o servidor: recolher a barra
    # acontece só no DOM. O `hidden` que o `tooltip_content/1` escreve é o
    # estado fechado do tooltip, e o JavaScript o tira no `mouseover` sem olhar
    # a barra — então é a classe que precisa segurar a dica com a barra aberta.
    test "a dica fica escondida com a barra aberta e volta no modo só-ícones" do
      html =
        render_component(&sidebar_menu_button/1, %{
          tooltip: "Ir para bandas",
          inner_block: bloco("Bandas")
        })

      classes = classes_da_dica(html)

      assert "hidden" in classes,
             "com a barra aberta o nome já está escrito ao lado do ícone"

      assert "group-data-[collapsible=icon]:block" in classes,
             "recolhida, a dica é o único lugar onde o nome do item aparece"
    end
  end

  describe "sidebar_menu_action/1" do
    test "é a ação que aparece ao lado de um item do menu" do
      html = render_component(&sidebar_menu_action/1, %{inner_block: bloco("…")})

      assert html =~ ~s(data-sidebar="menu-action")
    end
  end

  describe "sidebar_menu_badge/1" do
    test "mostra o contador ao lado de um item do menu" do
      html = render_component(&sidebar_menu_badge/1, %{inner_block: bloco("3")})

      assert html =~ ~s(data-sidebar="menu-badge")
      assert html =~ "3"
    end
  end

  describe "sidebar_menu_skeleton/1" do
    test "desenha o lugar do item enquanto o menu carrega" do
      html = render_component(&sidebar_menu_skeleton/1, %{})

      assert html =~ ~s(data-sidebar="menu-skeleton")
      assert html =~ ~s(data-sidebar="menu-skeleton-text")
      refute html =~ ~s(data-sidebar="menu-skeleton-icon")
    end

    test "reserva também o lugar do ícone quando pedido" do
      html = render_component(&sidebar_menu_skeleton/1, %{show_icon: true})

      assert html =~ ~s(data-sidebar="menu-skeleton-icon")
    end
  end

  describe "submenu" do
    test "sidebar_menu_sub/1 é a lista aninhada" do
      html = render_component(&sidebar_menu_sub/1, %{inner_block: bloco("itens")})

      assert html =~ "<ul"
      assert html =~ ~s(data-sidebar="menu-sub")
    end

    test "sidebar_menu_sub_item/1 é um item da lista aninhada" do
      html = render_component(&sidebar_menu_sub_item/1, %{inner_block: bloco("Banda Jovem")})

      assert html =~ "<li"
      assert html =~ "Banda Jovem"
    end

    test "sidebar_menu_sub_button/1 é o link do item aninhado" do
      html =
        render_component(&sidebar_menu_sub_button/1, %{
          size: "sm",
          is_active: true,
          inner_block: bloco("Banda Jovem")
        })

      assert html =~ ~s(data-sidebar="menu-sub-button")
      assert html =~ ~s(data-size="sm")
      assert html =~ ~s(data-active="true")
    end
  end

  defp classes_da_dica(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([data-part="content"]))
    |> LazyHTML.attribute("class")
    |> List.first()
    |> String.split()
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
