defmodule ChurchBandsWeb.Components.UI.CardTest do
  @moduledoc """
  As peças do cartão do SaladUI.

  A tela de convites usa `card/1` e `card_content/1`; as demais peças —
  cabeçalho, título, descrição e rodapé — completam o componente e existem
  para a próxima tela que precisar delas.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Card
  import Phoenix.LiveViewTest

  describe "card/1" do
    test "é a moldura com borda e sombra" do
      html = render_component(&card/1, %{inner_block: bloco("Conteúdo")})

      assert html =~ "Conteúdo"
      assert html =~ "border"
      assert html =~ "rounded-xl"
    end
  end

  describe "cabeçalho do cartão" do
    test "card_header/1 empilha título e descrição" do
      html = render_component(&card_header/1, %{inner_block: bloco("cabeçalho")})

      assert html =~ "cabeçalho"
      assert html =~ "flex flex-col"
    end

    test "card_title/1 é um <h3>" do
      html = render_component(&card_title/1, %{inner_block: bloco("Convites")})

      assert html =~ "<h3"
      assert html =~ "Convites"
    end

    test "card_description/1 é o texto de apoio do título" do
      html = render_component(&card_description/1, %{inner_block: bloco("Vale por 7 dias")})

      assert html =~ "<p"
      assert html =~ "Vale por 7 dias"
      assert html =~ "text-muted-foreground"
    end
  end

  describe "card_content/1" do
    test "é a área principal do cartão" do
      html = render_component(&card_content/1, %{inner_block: bloco("formulário")})

      assert html =~ "formulário"
      assert html =~ "p-6"
    end
  end

  describe "card_footer/1" do
    test "alinha as ações ao pé do cartão" do
      html = render_component(&card_footer/1, %{inner_block: bloco("Salvar")})

      assert html =~ "Salvar"
      assert html =~ "items-center"
    end
  end

  describe "classe extra" do
    test "a classe passada se junta às do componente" do
      html = render_component(&card_content/1, %{class: "pt-6", inner_block: bloco("x")})

      assert html =~ "pt-6"
    end
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
