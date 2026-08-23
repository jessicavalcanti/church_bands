defmodule ChurchBandsWeb.Components.UI.HelpersTest do
  @moduledoc """
  Os auxiliares que sustentam os componentes do SaladUI.

  Dois deles carregam ajuste local e por isso merecem teste próprio:
  `field_errors/1`, que só mostra erro de campo já preenchido (US 1.9), e
  `get_translator_from_config/0`, cuja chave mora em `:church_bands` porque a
  biblioteca é dependência só de desenvolvimento e não chegaria ao runtime.

  O caso é **síncrono** de propósito: parte dele apaga a configuração do
  tradutor de erros, que é global e valeria para os testes rodando em paralelo.
  """
  use ExUnit.Case, async: false

  use Phoenix.Component

  import ChurchBandsWeb.Components.UI.Helpers
  import ExUnit.CaptureIO
  import Phoenix.LiveViewTest

  describe "field_errors/1" do
    test "não mostra erro de campo que a pessoa ainda não preencheu" do
      assert field_errors(campo_com_erro()) == []
    end

    test "mostra o erro depois que o campo foi enviado" do
      assert field_errors(campo_com_erro(preenchido: true)) == ["não pode ficar em branco"]
    end

    test "devolve lista vazia para o que não é campo de formulário" do
      assert field_errors(nil) == []
      assert field_errors("email") == []
    end
  end

  describe "has_error?/1" do
    test "é verdadeiro só quando há erro para mostrar" do
      refute has_error?(campo_com_erro())
      assert has_error?(campo_com_erro(preenchido: true))
      refute has_error?(nil)
    end
  end

  describe "event_mappings/1" do
    test "recolhe os atributos on-* e descarta o resto" do
      assert event_mappings(%{"on-open": "abriu", class: "p-2", id: "x"}) == %{"open" => "abriu"}
    end

    test "ignora manipulador nulo ou desligado" do
      assert event_mappings(%{"on-open": nil, "on-close": false}) == %{}
    end
  end

  describe "button_variant/1" do
    test "sem nada escolhido usa a variante e o tamanho padrão" do
      classes = button_variant(%{})

      assert classes =~ "bg-primary"
      assert classes =~ "h-9 px-4 py-2"
    end

    test "a variante escolhida troca as classes" do
      assert button_variant(%{variant: "outline"}) =~ "border border-input"
      assert button_variant(%{size: "sm"}) =~ "h-8 rounded-md px-3"
    end
  end

  describe "variant_class/2" do
    @config %{
      variants: %{
        variant: %{default: "cor-padrao", outline: "cor-contorno"},
        size: %{default: "tamanho-padrao", lg: "tamanho-grande"}
      },
      default_variants: %{variant: "default", size: "default"}
    }

    test "cai no padrão para a chave que não veio" do
      assert variant_class(@config, %{variant: "outline"}) =~ "cor-contorno"
      assert variant_class(@config, %{variant: "outline"}) =~ "tamanho-padrao"
    end

    test "usa os dois padrões quando não vem nada" do
      classes = variant_class(@config, %{})

      assert classes =~ "cor-padrao"
      assert classes =~ "tamanho-padrao"
    end
  end

  describe "style/1" do
    test "junta mapas e declarações soltas numa string de style" do
      resultado = style([%{color: "red"}, "font-size: 16px"])

      assert resultado =~ "color: red"
      assert resultado =~ "font-size: 16px"
      assert String.ends_with?(resultado, ";")
    end

    test "lista vazia não vira um atributo style vazio" do
      assert style([]) == ""
    end
  end

  describe "prepare_assign/1" do
    test "deriva id, nome e valor do campo do formulário" do
      field = to_form(%{"email" => "ana@exemplo.com"})[:email]

      assigns = prepare_assign(%{field: field, __changed__: %{}})

      assert assigns.name == "email"
      assert assigns.value == "ana@exemplo.com"
      assert is_nil(assigns.field)
    end

    test "campo vazio cai no default-value" do
      field = to_form(%{"email" => ""})[:email]

      assigns =
        prepare_assign(%{field: field, "default-value": "nome@exemplo.com", __changed__: %{}})

      assert assigns.value == "nome@exemplo.com"
    end
  end

  describe "as_child/1" do
    test "entrega o componente filho ao componente pai pelo atributo as" do
      html =
        render_component(&as_child/1, %{
          tag: &pai/1,
          child: &filho/1,
          class: "p-2",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Bandas" end}]
        })

      assert html =~ ~s(id="filho")
      assert html =~ "p-2"
      assert html =~ "Bandas"
    end
  end

  describe "tradução de erro sem o tradutor configurado" do
    setup do
      original = Application.get_env(:church_bands, :error_translator_function)
      Application.delete_env(:church_bands, :error_translator_function)

      on_exit(fn ->
        Application.put_env(:church_bands, :error_translator_function, original)
      end)
    end

    test "cai no substituto do SaladUI, que só interpola a mensagem" do
      campo =
        campo_com_erro(
          preenchido: true,
          erro: {"should be at least %{count} character(s)", [count: 8]}
        )

      assert field_errors(campo) == ["should be at least 8 character(s)"]
    end

    test "valor que não vira texto avisa e mostra \"invalid value\"" do
      campo = campo_com_erro(preenchido: true, erro: {"%{limite}", [limite: %{a: 1}]})

      aviso = capture_io(:stderr, fn -> assert field_errors(campo) == ["invalid value"] end)

      assert aviso =~ "error_translator_function"
    end
  end

  # O par usado por `as_child/1`: `pai/1` recebe o filho em `:as` e o chama no
  # próprio lugar, que é como o SaladUI imita o `asChild` do shadcn.
  defp pai(assigns) do
    ~H"""
    <.dynamic tag={@as} class={@class}>{render_slot(@inner_block)}</.dynamic>
    """
  end

  defp filho(assigns) do
    ~H"""
    <button id="filho" class={@class}>{render_slot(@inner_block)}</button>
    """
  end

  # Um `%Phoenix.HTML.FormField{}` com erro, opcionalmente já enviado — é
  # `used_input?/1` que separa "campo em branco" de "campo que a pessoa ainda
  # nem tocou".
  defp campo_com_erro(opts \\ []) do
    erro = Keyword.get(opts, :erro, {"can't be blank", []})

    params = if opts[:preenchido], do: %{"email" => ""}, else: %{}

    %Phoenix.HTML.FormField{
      id: "user_email",
      name: "user[email]",
      errors: [erro],
      field: :email,
      form: %Phoenix.HTML.Form{
        source: %{},
        impl: Phoenix.HTML.FormData.Map,
        id: "user",
        name: "user",
        params: params,
        data: %{},
        hidden: [],
        options: [],
        errors: []
      },
      value: ""
    }
  end
end
