defmodule ChurchBands.Accounts.PasswordResetToken do
  @moduledoc """
  Token de redefinição de senha (US 1.7).

  O token viaja no link do e-mail em texto claro, mas no banco fica apenas o
  seu hash SHA-256: um vazamento da tabela não permite redefinir a senha de
  ninguém. Vale por 1 hora e é de uso único — `used_at` marca o consumo.
  """
  use Ecto.Schema

  alias ChurchBands.Accounts.User

  @validity_in_minutes 60

  schema "password_reset_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Prazo de validade do link, em minutos.
  """
  def validity_in_minutes, do: @validity_in_minutes

  @doc """
  Gera um token novo para `user`.

  Devolve `{token, struct}`: o token em texto claro, que só existe aqui e
  segue para o e-mail, e a struct pronta para inserir, que guarda o hash.
  """
  def build(%User{} = user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    struct = %__MODULE__{
      user_id: user.id,
      token_hash: hash(token),
      expires_at: expires_at()
    }

    {token, struct}
  end

  @doc """
  Hash usado para procurar o token no banco.
  """
  def hash(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  @doc """
  Changeset que marca o token como usado, fechando o uso único.
  """
  def use_changeset(%__MODULE__{} = token) do
    Ecto.Changeset.change(token, used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Um token só é utilizável enquanto não tiver sido usado e estiver no prazo.
  """
  def usable?(%__MODULE__{used_at: nil, expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def usable?(%__MODULE__{}), do: false

  defp expires_at do
    DateTime.utc_now()
    |> DateTime.add(@validity_in_minutes, :minute)
    |> DateTime.truncate(:second)
  end
end
