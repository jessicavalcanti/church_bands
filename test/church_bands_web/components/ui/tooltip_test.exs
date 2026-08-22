defmodule ChurchBandsWeb.Components.UI.TooltipTest do
  @moduledoc """
  A dica (`tooltip`) do SaladUI.

  Ela aparece no portal presa aos itens do menu, montada por
  `sidebar_menu_button/1` sem id — o componente gera um. Aqui se testa o outro
  caminho: o id escolhido por quem monta, que é o que permite referenciar a
  dica em um teste ou em um `phx-click`.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Tooltip
  import Phoenix.LiveViewTest

  describe "tooltip/1" do
    test "mantém o id escolhido por quem monta" do
      html = render_component(&tooltip/1, %{id: "dica-bandas", inner_block: bloco("Bandas")})

      assert html =~ ~s(id="dica-bandas")
      assert html =~ ~s(data-component="tooltip")
    end

    test "sem id, gera um para o hook do SaladUI encontrar" do
      html = render_component(&tooltip/1, %{inner_block: bloco("Bandas")})

      assert html =~ ~s(id="tooltip-)
    end
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
