defmodule ChurchBands.Accounts.User do
  @moduledoc """
  Usuário do sistema.

  `global_role` cobre apenas os papéis de acesso total (Pastor e Líder de
  Louvor). "Líder de Banda" não é um papel global: ele é derivado de
  `bands.leader_id` e tratado no contexto `ChurchBands.Bands`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @global_roles [:member, :worship_leader, :pastor]

  schema "users" do
    field :email, :string
    field :name, :string
    field :phone, :string
    field :photo_url, :string
    field :global_role, Ecto.Enum, values: @global_roles, default: :member
    field :confirmed_at, :utc_datetime

    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Lista dos papéis globais aceitos.
  """
  def global_roles, do: @global_roles

  @doc """
  Changeset de criação de usuário com senha. Usado pelos seeds.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :phone, :photo_url, :global_role, :password, :confirmed_at])
    |> validate_required([:email, :name, :password])
    |> validate_email()
    |> validate_password()
  end

  @doc """
  Changeset de ativação de conta a partir de um convite (US 1.2).

  Só aceita nome e senha: o e-mail vem do convite e é definido
  programaticamente pelo contexto, nunca pelo formulário — o link de ativação
  vale apenas para o e-mail convidado. A senha exige confirmação.
  """
  def activation_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :password])
    |> validate_required([:name, :password])
    |> validate_length(:name, min: 2, max: 160)
    |> validate_confirmation(:password, required: true, message: "não confere com a senha")
    |> validate_password()
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.trim/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "precisa ser um e-mail válido"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, ChurchBands.Repo)
    |> unique_constraint(:email)
  end

  # Critérios mínimos de segurança da senha (US 1.2).
  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72)
    |> validate_format(:password, ~r/[a-zA-Z]/, message: "precisa conter ao menos uma letra")
    |> validate_format(:password, ~r/[0-9]/, message: "precisa conter ao menos um número")
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
