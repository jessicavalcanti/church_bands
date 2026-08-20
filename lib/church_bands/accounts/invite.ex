defmodule ChurchBands.Accounts.Invite do
  @moduledoc """
  Convite para uma pessoa criar conta no sistema.

  Enquanto o convite não for aceito a pessoa não tem conta nem acesso. O
  convite vale por 7 dias e pode ser reenviado ou cancelado por Pastor /
  Líder de Louvor.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Accounts.User

  @statuses [:pending, :accepted, :expired, :cancelled]
  @validity_in_days 7

  schema "invites" do
    field :email, :string
    field :token, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :expires_at, :utc_datetime

    belongs_to :invited_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Lista dos status aceitos.
  """
  def statuses, do: @statuses

  @doc """
  Prazo de validade de um convite, em dias.
  """
  def validity_in_days, do: @validity_in_days

  @doc """
  Changeset de criação. `invited_by_id` é definido programaticamente pelo
  contexto, nunca vindo dos parâmetros do formulário.
  """
  def create_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> update_change(:email, &String.trim/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "precisa ser um e-mail válido"
    )
    |> validate_length(:email, max: 160)
    |> put_change(:token, generate_token())
    |> put_change(:status, :pending)
    |> put_change(:expires_at, expires_at())
    |> unique_constraint(:email,
      name: :invites_email_pending_index,
      message: "já possui um convite pendente"
    )
  end

  @doc """
  Changeset de reenvio: gera um novo token e reinicia o prazo de validade,
  devolvendo o convite ao status pendente.
  """
  def resend_changeset(invite) do
    change(invite,
      token: generate_token(),
      status: :pending,
      expires_at: expires_at()
    )
    |> unique_constraint(:email,
      name: :invites_email_pending_index,
      message: "já possui um convite pendente"
    )
  end

  @doc """
  Changeset de mudança de status.
  """
  def status_changeset(invite, status) when status in @statuses do
    change(invite, status: status)
  end

  @doc """
  Um convite só é utilizável enquanto estiver pendente e dentro do prazo.
  """
  def usable?(%__MODULE__{status: :pending, expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def usable?(%__MODULE__{}), do: false

  defp expires_at do
    DateTime.utc_now()
    |> DateTime.add(@validity_in_days, :day)
    |> DateTime.truncate(:second)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
