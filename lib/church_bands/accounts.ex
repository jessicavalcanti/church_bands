defmodule ChurchBands.Accounts do
  @moduledoc """
  Contexto de usuários, convites e autenticação.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Accounts.InviteNotifier
  alias ChurchBands.Accounts.User
  alias ChurchBands.Repo

  ## Usuários

  @doc """
  Busca um usuário pelo id, ou `nil`.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Busca um usuário pelo e-mail, ou `nil`. A coluna é `citext`, então a busca
  não diferencia maiúsculas de minúsculas.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.trim(email))
  end

  @doc """
  Cria um usuário.

  Usado pelos seeds e pela ativação de conta (US 1.2).
  """
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  `true` para quem tem acesso total ao sistema: Pastor e Líder de Louvor.
  """
  def full_access?(%User{global_role: role}), do: role in [:pastor, :worship_leader]
  def full_access?(_), do: false

  ## Convites

  @doc """
  Lista os convites, mais recentes primeiro, com quem convidou pré-carregado.

  Antes de listar, marca como expirados os convites pendentes cujo prazo já
  passou, para que o status exibido na tela seja sempre o real.
  """
  def list_invites do
    expire_overdue_invites()

    Invite
    |> order_by(desc: :inserted_at, desc: :id)
    |> preload(:invited_by)
    |> Repo.all()
  end

  @doc """
  Busca um convite pelo id, ou `nil`.
  """
  def get_invite(id) do
    Invite
    |> Repo.get(id)
    |> Repo.preload(:invited_by)
  end

  @doc """
  Busca um convite pelo token, ou `nil`.
  """
  def get_invite_by_token(token) when is_binary(token) do
    Repo.get_by(Invite, token: token)
  end

  @doc """
  Cria um convite para `email`, enviado por `invited_by`.

  Recusa quando o e-mail já pertence a uma conta existente ou quando já há um
  convite pendente para ele. Em caso de sucesso, dispara o e-mail com o link
  de ativação.
  """
  def create_invite(attrs, %User{} = invited_by) do
    expire_overdue_invites()

    changeset =
      %Invite{invited_by_id: invited_by.id}
      |> Invite.create_changeset(attrs)
      |> validate_email_available()

    with {:ok, invite} <- Repo.insert(changeset) do
      deliver_invite(invite)
    end
  end

  @doc """
  Reenvia um convite: gera um novo token, reinicia o prazo de validade e
  dispara o e-mail novamente.

  Convites já aceitos não podem ser reenviados.
  """
  def resend_invite(%Invite{status: :accepted}), do: {:error, :already_accepted}

  def resend_invite(%Invite{} = invite) do
    with {:ok, invite} <- invite |> Invite.resend_changeset() |> Repo.update() do
      deliver_invite(invite)
    end
  end

  @doc """
  Cancela um convite. Convites já aceitos não podem ser cancelados.
  """
  def cancel_invite(%Invite{status: :accepted}), do: {:error, :already_accepted}
  def cancel_invite(%Invite{status: :cancelled} = invite), do: {:ok, invite}

  def cancel_invite(%Invite{} = invite) do
    invite
    |> Invite.status_changeset(:cancelled)
    |> Repo.update()
  end

  @doc """
  Changeset em branco para alimentar o formulário de novo convite.
  """
  def change_invite(%Invite{} = invite \\ %Invite{}, attrs \\ %{}) do
    Invite.create_changeset(invite, attrs)
  end

  @doc """
  Marca como expirados os convites pendentes cujo `expires_at` já passou.
  Devolve a quantidade de convites atualizados.
  """
  def expire_overdue_invites do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Invite
      |> where([i], i.status == :pending and i.expires_at <= ^now)
      |> Repo.update_all(set: [status: :expired, updated_at: now])

    count
  end

  defp validate_email_available(changeset) do
    email = Ecto.Changeset.get_field(changeset, :email)

    if is_binary(email) and get_user_by_email(email) do
      Ecto.Changeset.add_error(changeset, :email, "já possui uma conta no sistema")
    else
      changeset
    end
  end

  defp deliver_invite(invite) do
    invite = Repo.preload(invite, :invited_by)

    case InviteNotifier.deliver_invite(invite) do
      {:ok, _} -> {:ok, invite}
      {:error, reason} -> {:error, {:delivery_failed, reason}}
    end
  end
end
