defmodule ChurchBandsWeb.Components.UI.Checkbox do
  @moduledoc """
  Implementation of checkbox component from https://ui.shadcn.com/docs/components/checkbox

  ## Examples:

      <.checkbox name="terms" id="terms" />

      <div class="flex items-center space-x-2">
        <.checkbox id="terms" name="terms" />
        <.label for="terms">Accept terms and conditions</.label>
      </div>

      <.checkbox id="remember_me" name="remember_me" label="Remember me" />

      <.form for={@form} as={:user} phx-change="validate">
        <.checkbox field={@form[:accept_terms]} label="I accept the terms and conditions" />
      </.form>
  """
  use ChurchBandsWeb.Components.UI, :component

  # Ajuste local (US 3.1): o componente original chamava
  # `Phoenix.HTML.Form.normalize_value/2` pelo nome inteiro, e o `credo
  # --strict` do projeto pede o alias no topo do módulo.
  alias Phoenix.HTML.Form

  @doc """
  Renders a checkbox input with SaladUI styling.

  ## Options

  * `:id` - The id to apply to the checkbox
  * `:name` - The name to apply to the input field
  * `:value` - The current value of the checkbox
  * `:default-value` - The default value of the checkbox, either `true`, `false`, "true", "false"
  * `:disabled` - Whether the checkbox is disabled
  * `:field` - A Phoenix form field
  * `:class` - Additional classes to add to the checkbox
  """
  # Ajuste local (US 3.1): o componente original não declarava `:id` nem o
  # desenhava no `<input>`. Com `id` escrito à mão ele ia parar no `:global` e
  # aparecia; com `field={@form[:campo]}`, quem derivava o id era o
  # `prepare_assign/1` — e aí o atributo **sumia** do HTML, deixando o
  # `<.form_label field={...}>` com um `for` apontando para nada. Clicar no
  # rótulo não marcava a caixa, que é justamente o uso que o exemplo do
  # moduledoc acima anuncia. Declarar o atributo, como o `input` faz, resolve os
  # dois caminhos de uma vez.
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any, default: nil
  attr :"default-value", :any, values: [true, false, "true", "false"], default: false
  attr :field, Phoenix.HTML.FormField
  attr :class, :string, default: nil
  attr :rest, :global

  def checkbox(assigns) do
    assigns =
      prepare_assign(assigns)

    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns.value)
      end)

    ~H"""
    <input type="hidden" name={@name} value="false" />
    <input
      type="checkbox"
      class={
        classes([
          "peer h-4 w-4 shrink-0 rounded-xs border border-primary shadow-sm focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50 checked:bg-primary checked:focus:bg-primary checked:hover:bg-primary checked:text-primary-foreground",
          @class
        ])
      }
      id={@id}
      name={@name}
      value="true"
      checked={@checked}
      {@rest}
    />
    """
  end
end
