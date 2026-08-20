defmodule ChurchBandsWeb.PageController do
  use ChurchBandsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
