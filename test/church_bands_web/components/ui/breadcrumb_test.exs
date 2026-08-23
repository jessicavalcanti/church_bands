defmodule ChurchBandsWeb.Components.UI.BreadcrumbTest do
  @moduledoc """
  A reticência do breadcrumb do SaladUI.

  O breadcrumb do portal é montado por assign em `ChurchBandsWeb.Layouts` e
  exercido pelas telas em `ChurchBandsWeb.PortalTest`. A reticência é a peça
  que o caminho de hoje ainda não usa: ela marca os itens escondidos quando o
  caminho não cabe na tela.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Breadcrumb
  import Phoenix.LiveViewTest

  describe "breadcrumb_ellipsis/1" do
    test "desenha o sinal de itens escondidos" do
      html = render_component(&breadcrumb_ellipsis/1, %{})

      assert html =~ "<svg"
      assert html =~ "items-center"
    end

    test "aceita classe extra" do
      html = render_component(&breadcrumb_ellipsis/1, %{class: "md:hidden"})

      assert html =~ "md:hidden"
    end
  end
end
