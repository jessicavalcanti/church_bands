defmodule ChurchBands.Accounts.UserToken do
  @moduledoc """
  Token de sessão (DT-12), no formato do `phx.gen.auth`.

  **Uma linha por sessão aberta.** É o que separa este desenho do anterior, em
  que a sessão era o id do usuário mais um digest do `hashed_password` dentro do
  cookie: aquilo derrubava tudo na troca de senha — que era o que precisava ser
  resolvido —, mas o servidor não tinha lista de sessão nenhuma. Não dava para
  saber quantas existiam, nem apagar uma sem apagar as outras.

  O token **não é hasheado** aqui, e isso é do padrão: ele nasce de
  `:crypto.strong_rand_bytes/1` e vai para um cookie assinado, que o navegador
  não tem como forjar. O que viaja por e-mail é que precisa de hash no banco —
  é o caso do `ChurchBands.Accounts.PasswordResetToken`, que segue essa outra
  regra desde a US 1.7.

  A sessão vale 14 dias a contar da emissão. Passado o prazo, a linha
  continua no banco e a consulta deixa de encontrá-la: quem limpa o que venceu
  é o `delete_all` da troca de senha ou o `on_delete: :delete_all` do usuário.
  """
  use Ecto.Schema

  import Ecto.Query

  alias ChurchBands.Accounts.User
  alias ChurchBands.Accounts.UserToken

  @rand_size 32
  @session_validity_in_days 14

  schema "users_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Prazo de validade da sessão, em dias.
  """
  def session_validity_in_days, do: @session_validity_in_days

  @doc """
  Gera o token de uma sessão nova de `user`.

  Devolve `{token, struct}`: o token cru, que vai para o cookie assinado, e a
  linha pronta para inserir.
  """
  def build_session_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Consulta que devolve o dono de `token`, ou nada.

  Só encontra o que é do contexto `"session"` e está dentro do prazo — token de
  outro contexto não abre sessão, mesmo estando na mesma tabela.
  """
  def verify_session_token_query(token) do
    from t in by_token_and_context_query(token, "session"),
      join: u in assoc(t, :user),
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      select: u
  end

  @doc """
  Consulta de todos os tokens de `user`, em qualquer contexto.

  É o que a troca de senha apaga em bloco, e é a lista que o broadcast de
  desconexão percorre.
  """
  def by_user_query(%User{id: user_id}), do: from(t in UserToken, where: t.user_id == ^user_id)

  @doc """
  Consulta de um token de sessão específico — o que o logout apaga.
  """
  def by_session_token_query(token), do: by_token_and_context_query(token, "session")

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
