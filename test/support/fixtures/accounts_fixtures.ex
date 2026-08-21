defmodule ChurchBands.AccountsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Accounts`.
  """

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.PasswordResetToken
  alias ChurchBands.Repo

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

  # `Map.new/1` na entrada porque as três recebem tanto mapa quanto lista de
  # palavras-chave: `user_fixture/1` e `invite_fixture/1` sempre aceitaram as
  # duas formas, e sem a normalização estas estouravam com `BadMapError` na
  # lista — a mesma chamada funcionava ou não dependendo da fixture escolhida.
  def pastor_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :global_role, :pastor))

  def worship_leader_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :global_role, :worship_leader))

  def member_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :global_role, :member))

  @doc """
  Cria um token de redefinição de senha para `user` e devolve
  `{token, reset_token}` — o token em texto claro, como ele vai no link do
  e-mail, e a struct gravada.

  Aceita `:expires_at` e `:used_at` para montar os casos de link expirado e de
  link já usado.
  """
  def password_reset_token_fixture(user, attrs \\ %{}) do
    {token, reset_token} = PasswordResetToken.build(user)

    reset_token =
      reset_token
      |> Ecto.Changeset.change(Map.new(attrs))
      |> Repo.insert!()

    {token, reset_token}
  end

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
