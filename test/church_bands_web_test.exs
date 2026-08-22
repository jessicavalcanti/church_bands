defmodule ChurchBandsWebTest do
  @moduledoc """
  As entradas de `use ChurchBandsWeb`.

  Cada tela do sistema começa por uma delas, e o que elas injetam — os imports
  dos componentes, o backend de gettext, o sigil `~p` — é o que faz o resto do
  código compilar. Os módulos de exemplo abaixo são montados em tempo de
  execução, e não com um `use` no topo do arquivo, para que a falha apareça
  como teste vermelho em vez de erro de compilação da suíte inteira.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  describe "static_paths/0" do
    test "lista o que o endpoint serve como arquivo estático" do
      caminhos = ChurchBandsWeb.static_paths()

      assert "assets" in caminhos
      assert "images" in caminhos
      assert "fonts" in caminhos
      assert "favicon.ico" in caminhos
      assert "robots.txt" in caminhos
    end
  end

  describe "use ChurchBandsWeb, :html" do
    test "traz os componentes do SaladUI e o sigil de rotas" do
      module =
        compile_with(
          :html,
          quote do
            def exemplo(var!(assigns)), do: ~H|<.button>Enviar</.button>|
            def caminho, do: ~p"/bands"
          end
        )

      assert render_component(&module.exemplo/1, %{}) =~ "Enviar"
      assert module.caminho() == "/bands"
    end
  end

  describe "use ChurchBandsWeb, :live_view" do
    test "monta uma LiveView com os mesmos componentes do :html" do
      module = compile_with(:live_view, quote(do: def(exemplo, do: button_variant(%{}))))

      assert Phoenix.LiveView in behaviours(module)
      assert is_binary(module.exemplo())
    end
  end

  describe "use ChurchBandsWeb, :live_component" do
    test "monta um LiveComponent com os mesmos componentes do :html" do
      module = compile_with(:live_component, quote(do: def(exemplo, do: button_variant(%{}))))

      assert Phoenix.LiveComponent in behaviours(module)
      assert is_binary(module.exemplo())
    end
  end

  describe "use ChurchBandsWeb, :controller" do
    test "monta um controller com o sigil de rotas" do
      module = compile_with(:controller, quote(do: def(exemplo, do: ~p"/bands")))

      assert Plug in behaviours(module)
      assert module.exemplo() == "/bands"
    end
  end

  describe "use ChurchBandsWeb, :channel" do
    test "monta um canal" do
      module = compile_with(:channel)

      assert Phoenix.Channel in behaviours(module)
    end
  end

  describe "use ChurchBandsWeb, :router" do
    test "monta um router, que é um plug" do
      module = compile_with(:router)

      assert Plug in behaviours(module)
    end
  end

  describe "use ChurchBandsWeb, :verified_routes" do
    test "aponta o sigil ~p para o router da aplicação" do
      module = compile_with(:verified_routes, quote(do: def(exemplo, do: ~p"/admin/invites")))

      assert module.exemplo() == "/admin/invites"
    end
  end

  # Cada chamada precisa de um nome de módulo próprio: recriar o mesmo nome
  # deixa a VM com duas versões carregadas e um aviso de redefinição.
  defp compile_with(which, extra \\ nil) do
    name = Module.concat(__MODULE__, "Exemplo#{System.unique_integer([:positive])}")

    body =
      quote do
        use ChurchBandsWeb, unquote(which)

        unquote(extra)
      end

    {:module, module, _binary, _result} = Module.create(name, body, Macro.Env.location(__ENV__))
    module
  end

  defp behaviours(module) do
    module.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
  end
end
