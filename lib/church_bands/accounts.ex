defmodule ChurchBands.Accounts do
  @moduledoc """
  Contexto de usuários, convites e autenticação.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Accounts.InviteNotifier
  alias ChurchBands.Accounts.User
  alias ChurchBands.Repo
  alias Ecto.Multi

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
  Cria um usuário. Usado pelos seeds.
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

  @doc """
  Ativa a conta a partir de um convite utilizável, criando o usuário com o
  e-mail do convite e marcando o convite como aceito.

  O e-mail **nunca** vem de `attrs`: o link de ativação vale apenas para o
  e-mail convidado. `attrs` traz somente nome, senha e confirmação de senha.

  Devolve `{:error, :invalid_invite}` quando o convite não está mais
  utilizável (cancelado, já aceito ou expirado) e `{:error, :email_taken}`
  quando o e-mail convidado já ganhou uma conta nesse meio-tempo.
  """
  def accept_invite(%Invite{} = invite, attrs) do
    if Invite.usable?(invite) do
      do_accept_invite(invite, attrs)
    else
      {:error, :invalid_invite}
    end
  end

  @doc """
  Busca o convite de `token` e o devolve apenas se ainda estiver utilizável
  (pendente e dentro do prazo). Caso contrário, `nil`.

  Usado pela tela de ativação para decidir entre mostrar o formulário ou a
  mensagem de link inválido.
  """
  def get_usable_invite_by_token(token) when is_binary(token) do
    case get_invite_by_token(token) do
      %Invite{} = invite -> if Invite.usable?(invite), do: invite
      nil -> nil
    end
  end

  @doc """
  Changeset em branco para alimentar o formulário de ativação de conta.
  """
  def change_user_activation(%User{} = user \\ %User{}, attrs \\ %{}) do
    User.activation_changeset(user, attrs)
  end

  ## Autenticação

  @doc """
  Verifica e-mail e senha.

  Devolve `{:ok, user}` quando as credenciais conferem e a conta está ativa.
  Em qualquer outro caso devolve `{:error, :invalid_credentials}` — sem
  distinguir e-mail inexistente de senha errada, para não revelar quais
  e-mails têm conta. Quando o e-mail não existe ainda assim gastamos o tempo
  de um hash, para que a resposta não denuncie a diferença.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    case get_user_by_email(email) do
      %User{} = user ->
        cond do
          not Bcrypt.verify_pass(password, user.hashed_password) -> {:error, :invalid_credentials}
          is_nil(user.confirmed_at) -> {:error, :invalid_credentials}
          true -> {:ok, user}
        end

      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_email, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp do_accept_invite(invite, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # E-mail e `confirmed_at` são definidos aqui, e não em `cast/3`, para que o
    # formulário não consiga escolher para qual e-mail a conta é criada.
    user_changeset =
      %User{}
      |> User.activation_changeset(attrs)
      |> Ecto.Changeset.put_change(:email, invite.email)
      |> Ecto.Changeset.put_change(:confirmed_at, now)
      |> Ecto.Changeset.unique_constraint(:email)

    Multi.new()
    |> Multi.insert(:user, user_changeset)
    |> Multi.update(:invite, Invite.status_changeset(invite, :accepted))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        {:ok, user}

      {:error, :user, changeset, _changes} ->
        if Keyword.has_key?(changeset.errors, :email) do
          {:error, :email_taken}
        else
          {:error, changeset}
        end

      {:error, :invite, _changeset, _changes} ->
        {:error, :invalid_invite}
    end
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
