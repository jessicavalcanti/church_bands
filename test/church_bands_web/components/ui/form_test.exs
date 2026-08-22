defmodule ChurchBandsWeb.Components.UI.FormTest do
  @moduledoc """
  As peças de formulário do SaladUI.

  O trio rótulo–campo–mensagem é usado por todas as telas de cadastro, e o
  ajuste local do `form_message/1` (US 1.9) é o que faz a senha curta **e** sem
  número mostrar os dois problemas de uma vez, em vez de um de cada vez.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Form
  import Phoenix.LiveViewTest

  describe "form_control/1" do
    test "é um invólucro que só entrega o que está dentro" do
      html = render_component(&form_control/1, %{inner_block: bloco("<input>")})

      assert html =~ "&lt;input&gt;"
    end
  end

  describe "form_description/1" do
    test "explica o campo abaixo dele" do
      html =
        render_component(&form_description/1, %{
          inner_block: bloco("Use o e-mail da pessoa convidada.")
        })

      assert html =~ "<p"
      assert html =~ "Use o e-mail da pessoa convidada."
      assert html =~ "text-muted-foreground"
    end
  end

  describe "form_message/1" do
    test "mostra a mensagem escrita à mão quando ela vem no bloco" do
      html = render_component(&form_message/1, %{inner_block: bloco("Escolha o naipe")})

      assert html =~ "Escolha o naipe"
      assert html =~ "text-destructive"
    end

    test "mostra todos os erros passados em errors, e não só o primeiro" do
      html =
        render_component(&form_message/1, %{
          errors: ["precisa ter ao menos 8 caracteres", "precisa conter ao menos um número"]
        })

      assert html =~ "precisa ter ao menos 8 caracteres"
      assert html =~ "precisa conter ao menos um número"
    end

    test "sem erro e sem bloco não desenha nada" do
      html = render_component(&form_message/1, %{})

      assert String.trim(html) == ""
    end
  end

  defp bloco(texto) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> texto end}]
  end
end
