defmodule ChurchBands.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ChurchBands.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias ChurchBands.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ChurchBands.DataCase
    end
  end

  setup tags do
    ChurchBands.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(ChurchBands.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Conta as consultas ao banco que `fun` dispara e falha se não forem exatamente
  `expected`. Devolve o que `fun` devolveu.

      assert_queries(1, fn -> Schedule.list_upcoming_events_for_user(user) end)

  Existe para "isto é uma consulta só" ser um teste, e não uma leitura de log:
  uma tela que hoje carrega tudo de uma vez volta a ter N+1 no dia em que um
  `preload` a mais parecer inofensivo, e nada acusa. A contagem sai do evento
  `[:church_bands, :repo, :query]` que o Ecto já emite por `:telemetry` — nada
  de novo precisa ser instrumentado.

  O manipulador do `:telemetry` é global e roda no processo que fez a consulta,
  então ele só conta o que veio **deste** processo: em suíte assíncrona os
  outros testes estão consultando ao mesmo tempo, e sem o recorte a contagem
  seria de todo mundo.
  """
  def assert_queries(expected, fun) when is_integer(expected) and is_function(fun, 0) do
    ref = make_ref()
    test = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:church_bands, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test, do: send(test, {ref, :query})
      end,
      nil
    )

    try do
      result = fun.()
      counted = count_queries(ref, 0)

      assert counted == expected,
             "esperava #{expected} consulta(s) ao banco, e o bloco fez #{counted}"

      result
    after
      :telemetry.detach({__MODULE__, ref})
    end
  end

  defp count_queries(ref, counted) do
    receive do
      {^ref, :query} -> count_queries(ref, counted + 1)
    after
      0 -> counted
    end
  end
end
