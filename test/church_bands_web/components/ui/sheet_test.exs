defmodule ChurchBandsWeb.Components.UI.SheetTest do
  @moduledoc """
  As peças da gaveta (`sheet`) do SaladUI, que é a barra lateral no celular.

  A gaveta em uso aparece no portal, montada por `sidebar/1` quando
  `is_mobile` é verdadeiro. As peças de dentro — cabeçalho, título, descrição,
  rodapé e os gatilhos de abrir e fechar — são o contrato com o hook
  JavaScript: `data-part` diz ao hook o que é cada elemento e `data-action`,
  o que ele faz ao ser clicado.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Sheet
  import Phoenix.LiveViewTest

  describe "sheet_trigger/1" do
    test "é o elemento que manda abrir a gaveta" do
      html = render_component(&sheet_trigger/1, %{inner_block: bloco("Abrir menu")})

      assert html =~ ~s(data-part="trigger")
      assert html =~ ~s(data-action="open")
      assert html =~ "Abrir menu"
    end
  end

  describe "sheet_close/1" do
    test "é o elemento que manda fechar a gaveta" do
      html = render_component(&sheet_close/1, %{inner_block: bloco("Fechar")})

      assert html =~ ~s(data-part="close-trigger")
      assert html =~ ~s(data-action="close")
    end
  end

  describe "cabeçalho da gaveta" do
    test "sheet_header/1 agrupa título e descrição" do
      html = render_component(&sheet_header/1, %{inner_block: bloco("cabeçalho")})

      assert html =~ "cabeçalho"
      assert html =~ "flex flex-col"
    end

    test "sheet_title/1 é um <h3> marcado como título" do
      html = render_component(&sheet_title/1, %{inner_block: bloco("Grupo de Louvor")})

      assert html =~ "<h3"
      assert html =~ ~s(data-part="title")
      assert html =~ "Grupo de Louvor"
    end

    test "sheet_description/1 é o texto de apoio do título" do
      html = render_component(&sheet_description/1, %{inner_block: bloco("Escolha uma tela")})

      assert html =~ "<p"
      assert html =~ ~s(data-part="description")
      assert html =~ "Escolha uma tela"
    end
  end

  describe "sheet_footer/1" do
    test "empilha as ações ao pé da gaveta" do
      html = render_component(&sheet_footer/1, %{inner_block: bloco("Sair")})

      assert html =~ "Sair"
      assert html =~ "flex-col-reverse"
    end
  end

  describe "classe extra" do
    test "a classe passada se junta às do componente" do
      html =
        render_component(&sheet_title/1, %{class: "text-lg", inner_block: bloco("Título")})

      assert html =~ "text-lg"
    end
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
