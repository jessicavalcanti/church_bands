defmodule ChurchBandsWeb.Components.UI.Textarea do
  @moduledoc """
  Implementation of a textarea component for multi-line text input.

  ## Examples:

      <.textarea field={f[:description]} placeholder="Type your message here" />
      <.textarea rows="6" placeholder="Add your comments" value={@description} />
  """
  use ChurchBandsWeb.Components.UI, :component

  @doc """
  Renders a form textarea.

  ## Options

  * `:id` - The id to use for the textarea
  * `:name` - The name to use for the textarea
  * `:value` - The value to pre-populate the textarea with
  * `:field` - A form field struct to build the textarea from
  * `:class` - Additional CSS classes to apply
  * `:rows` - Number of visible text lines (passed through as rest)
  * `:placeholder` - Placeholder text (passed through as rest)
  * `:disabled` - Whether the textarea is disabled (passed through as rest)
  * `:required` - Whether the textarea is required (passed through as rest)
  """
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :class, :any, default: nil
  # Ajuste local (US 1.9): `placeholder`, `required`, `autocomplete` e `maxlength`
  # já estão documentados acima, mas faltavam na lista — sem eles o atributo é
  # descartado em silêncio.
  attr :rest, :global,
    include:
      ~w(autocomplete disabled form rows cols maxlength minlength placeholder readonly required)

  def textarea(assigns) do
    assigns = prepare_assign(assigns)

    ~H"""
    <textarea
      id={@id}
      name={@name}
      class={
        classes([
          "min-h-[80px] border-input bg-background flex w-full rounded-md border px-3 py-2 text-sm placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] disabled:cursor-not-allowed disabled:opacity-50",
          @class
        ])
      }
      {@rest}
    ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
    """
  end
end
