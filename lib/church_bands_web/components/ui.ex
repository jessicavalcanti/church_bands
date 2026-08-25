defmodule ChurchBandsWeb.Components.UI do
  @moduledoc """
  A base dos componentes do [SaladUI](https://hexdocs.pm/salad_ui) copiados
  para dentro do projeto.

  `mix salad.install` trouxe 41 componentes para `components/ui/`; a Fase 1 usa
  18, e os outros 22 foram apagados na revisão de fechamento da fase (R-16) —
  eram 33% de todo o `lib/` sem uma tela sequer que os chamasse. Quando um
  deles fizer falta, ele volta um a um, e aí nasce medido pela cobertura como
  qualquer outro código do projeto — foi assim que o `checkbox` voltou na
  US 3.1 e o `toast` na #87.

  **Repor um componente é copiar o arquivo da dependência**, não rodar a tarefa
  de instalação de novo: `mix salad.install` copia os 41 de uma vez e traria de
  volta os 22 apagados. A versão 1.0 do SaladUI não tem `mix salad.add`, então
  o caminho é o mesmo que o instalador faz por arquivo — copiar
  `deps/salad_ui/lib/salad_ui/<componente>.ex` para cá trocando `SaladUI` pelo
  prefixo deste módulo, rodar `mix format` e acrescentar o `import` na lista
  abaixo. É a filosofia do shadcn: o componente é do projeto, e o upstream é
  ponto de partida, não dependência de runtime.

  Este módulo é o que sobra de comum entre eles:

    * `use ChurchBandsWeb.Components.UI, :component` — o cabeçalho de todo
      componente: `Phoenix.Component`, os helpers e o `classes/1` que resolve
      as classes do Tailwind pelo `TwMerge`
    * `use ChurchBandsWeb.Components.UI` — importa de uma vez os componentes
      instalados. O projeto não usa este caminho: `ChurchBandsWeb` importa a
      dedo os que toda tela precisa (botão, campo, rótulo, cartão…) e cada
      módulo importa o resto por conta. **Ao trazer um componente de volta,
      acrescente o `import` dele na lista abaixo**, senão este caminho passa a
      mentir sobre o que existe

  `ChurchBandsWeb.Components.UI.LiveView` continua aqui mesmo sem ninguém
  chamá-lo: é a ponte servidor → componente (`send_command/4`) que o `sheet` e
  o `tooltip` documentam, e não é um componente que `mix salad.add` saiba
  repor.
  """

  def component do
    quote do
      use Phoenix.Component

      import ChurchBandsWeb.Components.UI.Helpers

      alias Phoenix.LiveView.JS

      defp classes(input) do
        TwMerge.merge(List.flatten(input))
      end
    end
  end

  @doc """
  When used, dispatch to the appropriate macro.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__(_) do
    quote do
      import ChurchBandsWeb.Components.UI.Alert
      import ChurchBandsWeb.Components.UI.Avatar
      import ChurchBandsWeb.Components.UI.Badge
      import ChurchBandsWeb.Components.UI.Breadcrumb
      import ChurchBandsWeb.Components.UI.Button
      import ChurchBandsWeb.Components.UI.Card
      import ChurchBandsWeb.Components.UI.Checkbox
      import ChurchBandsWeb.Components.UI.DropdownMenu
      import ChurchBandsWeb.Components.UI.Form
      import ChurchBandsWeb.Components.UI.Helpers
      import ChurchBandsWeb.Components.UI.Input
      import ChurchBandsWeb.Components.UI.Label
      import ChurchBandsWeb.Components.UI.Separator
      import ChurchBandsWeb.Components.UI.Sheet
      import ChurchBandsWeb.Components.UI.Sidebar
      import ChurchBandsWeb.Components.UI.Skeleton
      import ChurchBandsWeb.Components.UI.Table
      import ChurchBandsWeb.Components.UI.Textarea
      import ChurchBandsWeb.Components.UI.Toast
      import ChurchBandsWeb.Components.UI.Tooltip
    end
  end
end
