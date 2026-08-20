defmodule ChurchBands.Bands do
  @moduledoc """
  Contexto de bandas e vínculos de membros.

  Autorização (US 1.3): criar e excluir bandas é exclusivo de Pastor e Líder
  de Louvor; editar é permitido a eles e também ao próprio Líder da Banda.
  As funções `manage_bands?/1` e `edit_band?/2` são a fonte única dessa
  regra — as LiveViews as consultam antes de agir, nunca apenas escondendo o
  botão na tela.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Repo

  ## Autorização

  @doc """
  `true` para quem pode criar e excluir bandas: Pastor e Líder de Louvor.
  """
  def manage_bands?(user), do: Accounts.full_access?(user)

  @doc """
  `true` para quem pode editar `band`: Pastor, Líder de Louvor ou o próprio
  Líder da Banda.
  """
  def edit_band?(%User{} = user, %Band{} = band) do
    manage_bands?(user) or band.leader_id == user.id
  end

  def edit_band?(_user, _band), do: false

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
