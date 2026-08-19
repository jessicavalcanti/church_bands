defmodule ChurchBands.AccountsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Accounts`.
  """

  alias ChurchBands.Accounts

  def unique_email, do: "user#{System.unique_integer([:positive])}@exemplo.com"

  @doc """
  Cria um usuário. Aceita `:global_role` para escolher o papel de acesso.
  """
  def user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Usuária de Teste",
        email: unique_email(),
        password: "senha123456",
        global_role: :member,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, user} = Accounts.create_user(attrs)
    user
  end

  def pastor_fixture(attrs \\ %{}), do: user_fixture(Map.put(attrs, :global_role, :pastor))

  def worship_leader_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(attrs, :global_role, :worship_leader))

  def member_fixture(attrs \\ %{}), do: user_fixture(Map.put(attrs, :global_role, :member))

  @doc """
  Cria um convite pendente enviado por `invited_by` (um Líder de Louvor, por
  padrão).
  """
  def invite_fixture(attrs \\ %{}) do
    {invited_by, attrs} = Map.pop_lazy(Map.new(attrs), :invited_by, &worship_leader_fixture/0)
    attrs = Enum.into(attrs, %{email: unique_email()})

    {:ok, invite} = Accounts.create_invite(attrs, invited_by)
    invite
  end
end
