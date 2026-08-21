defmodule ChurchBandsWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use ChurchBandsWeb, :controller
      use ChurchBandsWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: ChurchBandsWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: ChurchBandsWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML

      # Componentes do projeto: header, icon, select nativo e a tabela com
      # slots. Ver `ChurchBandsWeb.CoreComponents` para o porquê de cada um.
      import ChurchBandsWeb.CoreComponents

      # Base visual: SaladUI, copiado para lib/church_bands_web/components/ui.
      # `Icon`, `Select` e `Table` ficam de fora de propósito — os três têm
      # equivalente do projeto em `CoreComponents`.
      import ChurchBandsWeb.Components.UI.Alert
      import ChurchBandsWeb.Components.UI.Badge
      import ChurchBandsWeb.Components.UI.Button
      import ChurchBandsWeb.Components.UI.Card
      import ChurchBandsWeb.Components.UI.Form
      import ChurchBandsWeb.Components.UI.Input
      import ChurchBandsWeb.Components.UI.Label
      import ChurchBandsWeb.Components.UI.Textarea
      import ChurchBandsWeb.Components.UI.Helpers, only: [button_variant: 1]

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias ChurchBandsWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ChurchBandsWeb.Endpoint,
        router: ChurchBandsWeb.Router,
        statics: ChurchBandsWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
