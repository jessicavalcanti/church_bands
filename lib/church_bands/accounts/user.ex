defmodule ChurchBands.Accounts.User do
  @moduledoc """
  Usuário do sistema.

  `global_role` cobre apenas os papéis de acesso total (Pastor e Líder de
  Louvor). "Líder de Banda" não é um papel global: ele é derivado de
  `bands.leader_id` e tratado no contexto `ChurchBands.Bands`.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [where: 3]

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
  Estreita uma query de usuários por um trecho do nome ou do e-mail; `nil` ou
  texto em branco devolvem a query intacta.

  Mora aqui porque é a mesma busca em dois lugares — a lista de pessoas
  (US 1.8) e o dropdown de integrantes da banda (US 1.4) — e uma busca que
  encontrasse gente diferente em cada tela seria a mesma pergunta com duas
  respostas.
  """
  def search(queryable, query) do
    case String.trim(query || "") do
      "" ->
        queryable

      query ->
        pattern = "%#{escape_like(query)}%"

        where(
          queryable,
          [u],
          ilike(u.name, ^pattern) or ilike(fragment("?::text", u.email), ^pattern)
        )
    end
  end

  # `%` e `_` digitados na busca são texto, não curinga.
  defp escape_like(query) do
    String.replace(query, ~r/([\\%_])/, "\\\\\\1")
  end

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

  @doc """
  Changeset de redefinição de senha (US 1.7).

  Só aceita senha e confirmação: a redefinição vem de um link enviado ao
  e-mail da conta, então quem ela é já está decidido pelo token — o
  formulário não escolhe usuário nem mexe em mais nada.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_confirmation(:password, required: true, message: "não confere com a senha")
    |> validate_password()
  end

  @doc """
  Changeset de edição do próprio perfil (US 1.5).

  Aceita **apenas** telefone e foto. Nome, e-mail e `global_role` ficam de
  fora do `cast/3` de propósito: o papel de acesso e a função na banda são
  dados estruturais, decididos por quem lidera, e não podem ser alterados pelo
  próprio músico nem forjando o parâmetro no formulário.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone, :photo_url])
    |> update_change(:phone, &trim/1)
    |> update_change(:photo_url, &trim/1)
    |> validate_phone()
    |> validate_photo_url()
  end

  @doc """
  Changeset de edição administrativa dos dados de outra pessoa (US 1.8).

  Aceita nome, telefone, foto e papel de acesso — o que Pastor e Líder de
  Louvor corrigem pela lista de pessoas. Fica **separado** de
  `profile_changeset/2` de propósito: o formulário do próprio perfil precisa
  continuar recusando nome e `global_role`, e um changeset só para os dois
  casos faria essa proteção depender de quem chama.

  E-mail e senha ficam de fora para todo mundo: o e-mail é a credencial que
  veio do convite (US 1.1), e a senha só o próprio dono troca, pelo link que
  chega no e-mail dele (US 1.7).

  Quem pode mudar o papel de acesso de quem é decidido no contexto, em
  `ChurchBands.Accounts.update_user/3` — depende de quem está editando e de
  quantas contas com acesso total sobrariam, e nenhuma das duas coisas o
  changeset sozinho enxerga.
  """
  def management_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :phone, :photo_url, :global_role])
    |> update_change(:name, &trim/1)
    |> update_change(:phone, &trim/1)
    |> update_change(:photo_url, &trim/1)
    |> validate_required([:name, :global_role], message: "não pode ficar em branco")
    |> validate_length(:name, min: 2, message: "precisa ter ao menos 2 caracteres")
    |> validate_length(:name, max: 160, message: "precisa ter no máximo 160 caracteres")
    |> validate_phone()
    |> validate_photo_url()
  end

  # Telefone é opcional e o formato varia demais (com DDD, com +55, com ou sem
  # traço) para ser cobrado ao pé da letra. Barramos só o que claramente não é
  # telefone, e deixamos passar a pontuação que as pessoas usam.
  defp validate_phone(changeset) do
    changeset
    |> validate_length(:phone, max: 20, message: "precisa ter no máximo 20 caracteres")
    |> validate_format(:phone, ~r/^[0-9()+\-\s.]+$/,
      message: "pode ter apenas números, espaços e os sinais + ( ) - ."
    )
    |> validate_digit_count(:phone, 8)
  end

  # Conta só os dígitos: "(11) 99999-9999" e "11999999999" são o mesmo telefone
  # com pontuação diferente, e é o número que precisa estar completo.
  defp validate_digit_count(changeset, field, minimum) do
    validate_change(changeset, field, fn ^field, value ->
      digits = value |> String.graphemes() |> Enum.count(&(&1 =~ ~r/[0-9]/))

      if digits >= minimum,
        do: [],
        else: [{field, "precisa ter ao menos #{minimum} números"}]
    end)
  end

  # A foto entra como endereço de uma imagem já hospedada — o upload de arquivo
  # não faz parte da Fase 1.
  defp validate_photo_url(changeset) do
    changeset
    |> validate_length(:photo_url, max: 500, message: "precisa ter no máximo 500 caracteres")
    |> validate_format(:photo_url, ~r{^https?://[^\s]+$},
      message: "precisa ser um endereço começando com http:// ou https://"
    )
  end

  # `cast/3` transforma string vazia em `nil`, então o trim precisa aceitá-lo.
  # Campo opcional em branco fica `nil`, e não string vazia gravada no banco.
  defp trim(nil), do: nil

  defp trim(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
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
