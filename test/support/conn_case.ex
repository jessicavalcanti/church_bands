defmodule ChurchBandsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ChurchBandsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ChurchBandsWeb.Endpoint

      use ChurchBandsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ChurchBandsWeb.ConnCase
    end
  end

  setup tags do
    ChurchBands.DataCase.setup_sandbox(tags)
    {:ok, conn: build_conn_from_own_ip()}
  end

  # Cada teste é um cliente diferente. Sem isso a suíte inteira chegaria do
  # mesmo `127.0.0.1` e esbarraria no limite de tentativas por IP
  # (`ChurchBands.RateLimit`) só por ser grande — e os testes do limite
  # passariam a depender da ordem em que os outros rodam.
  defp build_conn_from_own_ip do
    n = System.unique_integer([:positive])
    ip = {127, n |> div(65_536) |> rem(256), n |> div(256) |> rem(256), rem(n, 256)}

    Phoenix.ConnTest.build_conn()
    |> Map.put(:remote_ip, ip)
    |> Plug.Test.put_peer_data(%{address: ip, port: 0, ssl_cert: nil})
  end

  @doc """
  Coloca `user` na sessão da `conn`, simulando um usuário logado.

  Passa pelo mesmo `UserAuth.log_in_user/2` da tela de login, e não por um
  `put_session(:user_id, ...)` à mão: a sessão do teste guarda o que a de
  verdade guarda — inclusive a impressão digital da senha, sem a qual a sessão
  não vale.
  """
  def log_in_user(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> ChurchBandsWeb.UserAuth.log_in_user(user)
  end
end
