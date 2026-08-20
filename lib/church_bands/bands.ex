defmodule ChurchBands.Bands do
  @moduledoc """
  Contexto de bandas e vínculos de membros.

  Autorização: criar e excluir bandas é exclusivo de Pastor e Líder de Louvor
  (US 1.3); editar a banda e mexer nos seus integrantes (US 1.4) é permitido a
  eles e também ao próprio Líder da Banda. As funções `manage_bands?/1`,
  `edit_band?/2` e `manage_members?/2` são a fonte única dessa regra — as
  LiveViews as consultam antes de agir, nunca apenas escondendo o botão na
  tela.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Repo

  ## Autorização

  @doc """
  `true` para quem pode criar e excluir bandas: Pastor e Líder de Louvor.
  """
  def manage_bands?(user), do: Accounts.full_access?(user)

  @doc """
  `true` para quem responde por `band`: o próprio Líder da Banda, o Pastor ou
  o Líder de Louvor.

  É o predicado base das permissões por banda. `edit_band?/2` e
  `manage_members?/2` são nomes para o que está sendo autorizado; a regra em si
  mora aqui, num lugar só.
  """
  def band_leader?(%User{} = user, %Band{} = band) do
    manage_bands?(user) or band.leader_id == user.id
  end

  def band_leader?(_user, _band), do: false

  @doc """
  `true` para quem pode editar os dados de `band`.
  """
  def edit_band?(user, band), do: band_leader?(user, band)

  @doc """
  `true` para quem pode adicionar e remover integrantes de `band` (US 1.4).
  """
  def manage_members?(user, band), do: band_leader?(user, band)

  ## Bandas

  @doc """
  Lista as bandas em ordem alfabética, com o líder pré-carregado.
  """
  def list_bands do
    Band
    |> order_by(asc: :name)
    |> preload(:leader)
    |> Repo.all()
  end

  @doc """
  Busca uma banda pelo id, com o líder pré-carregado, ou `nil`.

  Aceita id em string (como vem dos parâmetros de rota) e devolve `nil` para
  ids que não sejam números inteiros, em vez de estourar.
  """
  def get_band(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get_band(id)
      _ -> nil
    end
  end

  def get_band(id) when is_integer(id) do
    Band
    |> Repo.get(id)
    |> Repo.preload(:leader)
  end

  @doc """
  Cria uma banda.

  Recusa com `{:error, changeset}` quando o líder escolhido não é um usuário
  com conta ativa — o Líder de Banda precisa poder entrar no sistema.
  """
  def create_band(attrs) do
    %Band{}
    |> Band.changeset(attrs)
    |> validate_leader_is_active()
    |> Repo.insert()
    |> preload_leader()
  end

  @doc """
  Atualiza uma banda.
  """
  def update_band(%Band{} = band, attrs) do
    band
    |> Band.changeset(attrs)
    |> validate_leader_is_active()
    |> Repo.update()
    |> preload_leader()
  end

  @doc """
  Exclui uma banda.
  """
  def delete_band(%Band{} = band), do: Repo.delete(band)

  @doc """
  Changeset para alimentar o formulário de banda.
  """
  def change_band(%Band{} = band \\ %Band{}, attrs \\ %{}) do
    Band.changeset(band, attrs)
  end

  @doc """
  Usuários que podem ser designados como Líder de Banda: qualquer conta já
  ativa, em ordem alfabética.
  """
  def list_leader_candidates do
    User
    |> where([u], not is_nil(u.confirmed_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  ## Integrantes

  @doc """
  Lista os vínculos de `band`, com o músico pré-carregado.

  Ordena por função (instrumentistas antes de vocalistas) e depois pelo nome,
  que é como a lista é lida na tela.
  """
  def list_members(%Band{} = band), do: list_members(band.id)

  def list_members(band_id) when is_integer(band_id) do
    from(m in BandMember,
      join: u in assoc(m, :user),
      where: m.band_id == ^band_id,
      order_by: [asc: m.type, asc: u.name],
      preload: [user: u]
    )
    |> Repo.all()
  end

  @doc """
  Busca um vínculo pelo id, com músico e banda pré-carregados, ou `nil`.

  Como `get_band/1`, aceita id em string e devolve `nil` para ids inválidos.
  """
  def get_member(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get_member(id)
      _ -> nil
    end
  end

  def get_member(id) when is_integer(id) do
    BandMember
    |> Repo.get(id)
    |> Repo.preload([:user, :band])
  end

  @doc """
  Vincula um músico a `band` com a função descrita em `attrs`.

  Recusa com `{:error, changeset}` quem ainda não ativou a conta e quem já é
  integrante da banda — o mesmo músico entra uma vez só em cada banda, mas
  pode estar em quantas bandas for.

  Quem pode chamar é decidido antes, por `manage_members?/2`.
  """
  def add_member(%Band{} = band, user_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{"band_id" => band.id, "user_id" => user_id})

    %BandMember{}
    |> BandMember.changeset(attrs)
    |> validate_member_is_active()
    |> Repo.insert()
    |> preload_member()
  end

  @doc """
  Desfaz o vínculo de um músico com a banda. O usuário continua no sistema.
  """
  def remove_member(%BandMember{} = member), do: Repo.delete(member)

  @doc """
  Changeset para alimentar o formulário de vínculo.
  """
  def change_member(%BandMember{} = member \\ %BandMember{}, attrs \\ %{}) do
    BandMember.changeset(member, attrs)
  end

  @doc """
  Músicos que ainda podem ser adicionados a `band`, filtrados por nome ou
  e-mail: apenas contas ativas e que ainda não são integrantes.

  Devolve lista vazia para busca em branco — a tela só sugere depois que a
  pessoa começa a digitar — e limita o resultado, já que é um autocomplete.
  """
  def search_member_candidates(%Band{} = band, query, limit \\ 8) do
    case String.trim(query || "") do
      "" ->
        []

      query ->
        pattern = "%#{escape_like(query)}%"

        from(u in User,
          where: not is_nil(u.confirmed_at),
          where: ilike(u.name, ^pattern) or ilike(fragment("?::text", u.email), ^pattern),
          where:
            u.id not in subquery(
              from m in BandMember, where: m.band_id == ^band.id, select: m.user_id
            ),
          order_by: [asc: u.name],
          limit: ^limit
        )
        |> Repo.all()
    end
  end

  # `%` e `_` digitados na busca são texto, não curinga.
  defp escape_like(query) do
    String.replace(query, ~r/([\\%_])/, "\\\\\\1")
  end

  # Espelha `validate_leader_is_active/1`: só entra na banda quem já aceitou o
  # convite e tem conta ativa (US 1.2).
  defp validate_member_is_active(changeset) do
    user_id = Ecto.Changeset.get_field(changeset, :user_id)

    if is_nil(user_id) or active_user?(user_id) do
      changeset
    else
      Ecto.Changeset.add_error(
        changeset,
        :user_id,
        "precisa ser alguém com conta ativa no sistema"
      )
    end
  end

  defp preload_member({:ok, member}), do: {:ok, Repo.preload(member, [:user, :band])}
  defp preload_member({:error, _} = error), do: error

  # O líder precisa existir e já ter ativado a conta (US 1.2). A `assoc_constraint`
  # do changeset cobre a existência no banco; aqui cobrimos a conta pendente,
  # que o banco não tem como saber.
  defp validate_leader_is_active(changeset) do
    leader_id = Ecto.Changeset.get_field(changeset, :leader_id)

    cond do
      is_nil(leader_id) ->
        changeset

      active_user?(leader_id) ->
        changeset

      true ->
        Ecto.Changeset.add_error(
          changeset,
          :leader_id,
          "precisa ser alguém com conta ativa no sistema"
        )
    end
  end

  defp active_user?(leader_id) do
    Repo.exists?(from u in User, where: u.id == ^leader_id and not is_nil(u.confirmed_at))
  end

  # `force: true` porque numa troca de líder o struct ainda carrega o líder
  # antigo já pré-carregado, e o preload normal não o substituiria.
  defp preload_leader({:ok, band}), do: {:ok, Repo.preload(band, :leader, force: true)}
  defp preload_leader({:error, _} = error), do: error
end
