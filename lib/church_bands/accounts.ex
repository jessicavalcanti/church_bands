defmodule ChurchBands.Accounts do
  @moduledoc """
  Contexto de usuários, convites e autenticação.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts.Invite
  alias ChurchBands.Accounts.InviteNotifier
  alias ChurchBands.Accounts.PasswordResetNotifier
  alias ChurchBands.Accounts.PasswordResetToken
  alias ChurchBands.Accounts.User
  alias ChurchBands.Repo
  alias Ecto.Multi

  ## Usuários

  @doc """
  Busca um usuário pelo id, ou `nil`.

  Aceita id em string (como vem dos parâmetros de rota) e devolve `nil` para
  ids que não sejam números inteiros, em vez de estourar.
  """
  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get_user(id)
      _ -> nil
    end
  end

  def get_user(id) when is_integer(id), do: Repo.get(User, id)

  @doc """
  Lista as contas já ativas em ordem alfabética, opcionalmente estreitadas por
  `query` — um trecho do nome ou do e-mail.

  Convite ainda não aceito **não** entra: enquanto ninguém ativou a conta não
  há pessoa para listar, e o convite segue sendo acompanhado em
  `/admin/invites` (US 1.1).
  """
  def list_users(query \\ nil) do
    User
    |> where([u], not is_nil(u.confirmed_at))
    |> User.search(query)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Busca um usuário pelo e-mail, ou `nil`. A coluna é `citext`, então a busca
  não diferencia maiúsculas de minúsculas.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: normalize_email(email))
  end

  @doc """
  O e-mail reduzido à sua forma de identificador: sem espaço nas pontas e em
  minúsculas, que é como a coluna `citext` já o trata.

  Existe com nome próprio porque o e-mail também é usado como **chave** fora do
  banco — é por ele que `ChurchBands.RateLimit` conta as tentativas —, e ali
  não há `citext` nenhum para igualar `Maria@` e `maria@`.
  """
  def normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
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
  Atualiza o próprio perfil de `user` (US 1.5): nome, telefone e foto.

  O que pode mudar é decidido por `User.profile_changeset/2`, que não aceita
  e-mail, papel de acesso nem função na banda — o e-mail é a credencial que
  veio do convite, e os outros dois mudam só pela mão de quem lidera.
  """
  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Changeset para alimentar o formulário de edição do próprio perfil.
  """
  def change_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Atualiza os dados de outra pessoa (US 1.8): nome, telefone, foto e papel de
  acesso.

  `actor` é quem está editando, e não é decoração — mudar papel de acesso é a
  ação mais sensível do sistema, e as duas travas dependem dele:

    * ninguém muda o **próprio** papel, nem para cima nem para baixo. Promover
      e rebaixar é sempre decisão de outra pessoa
    * o sistema nunca fica sem nenhuma conta com acesso total: rebaixar o
      último Pastor ou Líder de Louvor é recusado

  As duas recusas voltam como erro no campo `global_role`, e não como um
  `{:error, atom}` à parte: são erros de formulário, e é ao lado do campo que
  eles precisam ser lidos.

  Quem pode chamar é decidido antes, por `manage_users?/1`.
  """
  def update_user(%User{} = actor, %User{} = user, attrs) do
    actor
    |> change_user_management(user, attrs)
    |> Repo.update()
  end

  @doc """
  Changeset para alimentar o formulário de edição administrativa, já com as
  travas do papel de acesso aplicadas — assim a recusa aparece na tela no
  instante em que o papel é escolhido, e não só depois de salvar.
  """
  def change_user_management(%User{} = actor, %User{} = user, attrs \\ %{}) do
    user
    |> User.management_changeset(attrs)
    |> validate_role_change(actor, user)
  end

  @doc """
  `true` para quem tem acesso total ao sistema: Pastor e Líder de Louvor.
  """
  def full_access?(%User{global_role: role}), do: full_access_role?(role)
  def full_access?(_), do: false

  @doc """
  `true` para quem pode editar os dados de outra pessoa (US 1.8): o mesmo
  grupo do acesso total.

  Existe com nome próprio para que as telas de pessoas perguntem pelo que
  estão autorizando, e não pelo papel de quem pergunta.
  """
  def manage_users?(user), do: full_access?(user)

  defp full_access_role?(role), do: role in [:pastor, :worship_leader]

  # Sem mudança de papel não há o que travar: nome, telefone e foto qualquer
  # pessoa com acesso total corrige em qualquer conta, inclusive na sua.
  defp validate_role_change(changeset, actor, user) do
    case Ecto.Changeset.get_change(changeset, :global_role) do
      nil ->
        changeset

      new_role ->
        # As duas travas se cruzam em quem é o **único** com acesso total
        # tentando se rebaixar. Nesse encontro vale a do sistema sem acesso
        # total: mandar essa pessoa pedir a outra com acesso total seria
        # mandá-la procurar alguém que não existe — o caminho é promover
        # alguém antes.
        cond do
          leaving_system_without_full_access?(user, new_role) ->
            Ecto.Changeset.add_error(
              changeset,
              :global_role,
              "não pode ser rebaixado: o sistema ficaria sem ninguém com acesso total. " <>
                "Promova outra pessoa a Pastor(a) ou Líder de Louvor antes."
            )

          actor.id == user.id ->
            Ecto.Changeset.add_error(
              changeset,
              :global_role,
              "não pode ser mudado por você mesmo — outra pessoa com acesso total precisa fazer isso"
            )

          true ->
            changeset
        end
    end
  end

  defp leaving_system_without_full_access?(user, new_role) do
    full_access?(user) and not full_access_role?(new_role) and last_full_access?(user)
  end

  # "Último" é quem não tem companhia: nenhuma **outra** conta ativa com acesso
  # total. Conta pendente não conta — quem não consegue entrar não administra
  # nada.
  defp last_full_access?(%User{id: id}) do
    not Repo.exists?(
      from(u in User,
        where: u.id != ^id,
        where: not is_nil(u.confirmed_at),
        where: u.global_role in [:pastor, :worship_leader]
      )
    )
  end

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
    # O convite é relido antes de decidir: entre a tela de ativação abrir e o
    # formulário ser enviado ele pode ter sido cancelado, e a struct que a
    # LiveView guarda desde a montagem continuaria dizendo que está pendente.
    invite = Repo.reload(invite) || invite

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
  Impressão digital da senha atual de `user`, para ser guardada na sessão ao
  lado do id.

  A sessão vive num cookie assinado e o servidor não mantém lista de sessões
  abertas: sem isso, trocar a senha não teria como alcançar o cookie que já
  está no navegador de outra pessoa — quem entrou com a senha antiga
  continuaria dentro. Guardando junto uma impressão da senha, a própria troca
  invalida toda sessão anterior: `hashed_password` muda, a impressão deixa de
  bater e o cookie para de valer na requisição seguinte.

  É um digest do hash, e não o `hashed_password`: o cookie é assinado, mas
  legível por quem o tem em mãos, e o hash da senha não tem por que viajar
  até o navegador.
  """
  def session_fingerprint(%User{hashed_password: hashed_password}) do
    :sha256
    |> :crypto.hash(hashed_password)
    |> Base.url_encode64(padding: false)
  end

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

  ## Recuperação de senha

  @doc """
  Cria um token de redefinição para o dono de `email` e envia o link por
  e-mail.

  Devolve `:ok` em **qualquer** caso — e-mail inexistente, conta ainda não
  ativada ou pedido atendido. A tela não pode revelar quais e-mails têm conta,
  então o resultado da busca não pode vazar pelo valor de retorno.

  Convite ainda não aceito não tem conta e, portanto, não tem senha para
  redefinir: o pedido é silenciosamente ignorado.
  """
  def request_password_reset(email) when is_binary(email) do
    case get_user_by_email(email) do
      %User{confirmed_at: confirmed_at} = user when not is_nil(confirmed_at) ->
        deliver_password_reset(user)
        :ok

      _ ->
        :ok
    end
  end

  def request_password_reset(_email), do: :ok

  @doc """
  Busca o token de redefinição pelo valor que veio no link e o devolve, com o
  usuário pré-carregado, apenas se ainda for utilizável (não usado e dentro do
  prazo). Caso contrário, `nil`.

  Usada pela tela de redefinição para decidir entre mostrar o formulário ou a
  mensagem de link inválido.
  """
  def get_usable_reset_token(token) when is_binary(token) do
    hash = PasswordResetToken.hash(token)

    case Repo.get_by(PasswordResetToken, token_hash: hash) do
      %PasswordResetToken{} = reset_token ->
        if PasswordResetToken.usable?(reset_token), do: Repo.preload(reset_token, :user)

      nil ->
        nil
    end
  end

  def get_usable_reset_token(_token), do: nil

  @doc """
  Redefine a senha do dono de `token` com o que veio de `attrs` (senha e
  confirmação).

  A troca de senha e o consumo do token acontecem na mesma transação: ou a
  senha muda e o link morre junto, ou nada acontece. Os demais links de
  redefinição pendentes do usuário também são invalidados — depois de trocar a
  senha, nenhum pedido antigo pode continuar valendo.

  Devolve `{:error, :invalid_token}` quando o link já foi usado ou expirou, e
  `{:error, changeset}` quando a senha nova não passa nas validações.
  """
  def reset_password(token, attrs) when is_binary(token) do
    case get_usable_reset_token(token) do
      %PasswordResetToken{} = reset_token -> do_reset_password(reset_token, attrs)
      nil -> {:error, :invalid_token}
    end
  end

  @doc """
  Changeset em branco para alimentar o formulário de redefinição de senha.
  """
  def change_user_password(%User{} = user \\ %User{}, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  defp do_reset_password(%PasswordResetToken{} = reset_token, attrs) do
    user = reset_token.user
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:user, User.password_changeset(user, attrs))
    |> Multi.update(:token, PasswordResetToken.use_changeset(reset_token))
    |> Multi.update_all(:other_tokens, outstanding_reset_tokens(user, reset_token),
      set: [used_at: now]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
      # A rede de segurança do `case`. Os outros dois passos são um `change/2`
      # sem validação e um `update_all`: nenhum tem como devolver erro — o que
      # eles fazem, se a linha sumir do banco, é levantar `Ecto.StaleEntryError`.
      # Sem caminho para exercitá-lo, o ramo fica fora da contagem de cobertura.
      # coveralls-ignore-next-line
      {:error, _step, _value, _changes} -> {:error, :invalid_token}
    end
  end

  defp outstanding_reset_tokens(%User{id: user_id}, %PasswordResetToken{id: used_id}) do
    from(t in PasswordResetToken,
      where: t.user_id == ^user_id and t.id != ^used_id and is_nil(t.used_at)
    )
  end

  defp deliver_password_reset(%User{} = user) do
    {token, reset_token} = PasswordResetToken.build(user)

    with {:ok, _reset_token} <- Repo.insert(reset_token) do
      PasswordResetNotifier.deliver_reset(user, token)
    end
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

      # Mesma rede de segurança do `do_reset_password/2`: `status_changeset/2` é
      # um `change/2` sem validação, e não há como fazê-lo devolver erro.
      # coveralls-ignore-next-line
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
