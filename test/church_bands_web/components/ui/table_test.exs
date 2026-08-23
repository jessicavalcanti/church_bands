defmodule ChurchBandsWeb.Components.UI.TableTest do
  @moduledoc """
  As peças de tabela do SaladUI.

  `ChurchBandsWeb.CoreComponents.table/1` é montada sobre elas e já é exercida
  pelas telas de bandas, pessoas e convites. O que fica de fora dessa montagem
  — o rodapé de totais e a legenda — é testado aqui.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Table
  import Phoenix.LiveViewTest

  describe "table_footer/1" do
    test "é um <tfoot>, para a linha de totais" do
      html = render_component(&table_footer/1, %{inner_block: bloco("12 pessoas")})

      assert html =~ "<tfoot"
      assert html =~ "12 pessoas"
    end
  end

  describe "table_caption/1" do
    test "é a legenda que dá nome acessível à tabela" do
      html = render_component(&table_caption/1, %{inner_block: bloco("Convites enviados")})

      assert html =~ "<caption"
      assert html =~ "Convites enviados"
    end

    test "aceita classe extra" do
      html =
        render_component(&table_caption/1, %{class: "sr-only", inner_block: bloco("Convites")})

      assert html =~ "sr-only"
    end
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
