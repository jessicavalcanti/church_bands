defmodule ChurchBands.Bands do
  @moduledoc """
  Contexto de bandas e vínculos de membros.

  Autorização: criar e excluir bandas é exclusivo de Pastor e Líder de Louvor
  (US 1.3); editar a banda e mexer nos seus integrantes (US 1.4) é permitido a
  eles e também ao próprio Líder da Banda. As funções `manage_bands?/1`,
  `edit_band?/2` e `manage_members?/2` são a fonte única dessa regra — as
  LiveViews as consultam antes de agir, nunca apenas escondendo o botão na
  tela.

  O catálogo de instrumentos (US 2.8) mora aqui pelo mesmo motivo que os
  vínculos: é dele que sai a função de todo instrumentista. Curá-lo é de acesso
  total, e quem responde por isso é o hook `:ensure_full_access` da rota — não
  há predicado próprio aqui, como não há para convites: a tela inteira é
  restrita, e um `if` de permissão dentro dela seria um ramo sem como ser
  alcançado.
  """
  import Ecto.Query, warn: false

  alias ChurchBands.Accounts
  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Bands.Instrument
  alias ChurchBands.Repo
  alias ChurchBands.RouteId

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
  Lista as bandas em ordem alfabética, com o líder pré-carregado e o tamanho
  do elenco em `:roster_count`.
  """
  def list_bands do
    counts = roster_counts()

    Band
    |> order_by(asc: :name)
    |> preload(:leader)
    |> Repo.all()
    |> Enum.map(&%{&1 | roster_count: Map.get(counts, &1.id, 0)})
  end

  # Quantos sobem ao palco em cada banda, pela mesma regra de `list_roster/1`:
  # os vínculos mais o Líder de Banda, que conta mesmo sem vínculo. O
  # `bool_or` responde "o líder está entre os vínculos?" — quando a banda não
  # tem nenhum, ele vem `nil`, e o `coalesce` lê isso como "não está".
  defp roster_counts do
    from(b in Band,
      left_join: m in assoc(b, :band_members),
      group_by: b.id,
      select:
        {b.id,
         fragment(
           "count(?) + case when coalesce(bool_or(? = ?), false) then 0 else 1 end",
           m.id,
           m.user_id,
           b.leader_id
         )}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Busca uma banda pelo id, com o líder pré-carregado, ou `nil`.

  Aceita id em string (como vem dos parâmetros de rota) e devolve `nil` para
  ids que não sejam números inteiros, em vez de estourar.
  """
  def get_band(id) when is_binary(id), do: RouteId.get(id, &get_band/1)

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
      # `left_join` porque vocalista não tem instrumento: com `join` o elenco
      # perderia quem canta.
      left_join: i in assoc(m, :instrument),
      where: m.band_id == ^band_id,
      order_by: [asc: m.type, asc: u.name],
      preload: [user: u, instrument: i]
    )
    |> Repo.all()
  end

  @doc """
  Elenco de `band`: quem sobe para tocar, na ordem em que a banda se
  apresenta — o Líder de Banda primeiro, depois os demais.

  Cada item é um mapa com `:user`, `:member` e `:leader?`. O líder entra na
  lista **mesmo sem vínculo**, com `member: nil`, porque ele participa da
  apresentação desde o instante em que a banda é criada; nesse caso a tela
  cobra a função que falta. Quando ele já tem vínculo, aparece uma vez só, no
  topo, com a função dele.
  """
  def list_roster(%Band{} = band) do
    band = Repo.preload(band, :leader)

    {leader, rest} =
      band
      |> list_members()
      |> Enum.map(&%{user: &1.user, member: &1, leader?: &1.user_id == band.leader_id})
      |> Enum.split_with(& &1.leader?)

    case leader do
      [] -> [%{user: band.leader, member: nil, leader?: true} | rest]
      _ -> leader ++ rest
    end
  end

  @doc """
  O contrário de `list_roster/1`: as bandas de que `user` participa, em ordem
  alfabética.

  Cada item é um mapa com `:band`, `:member` e `:leader?`, no mesmo formato do
  elenco. Uma banda que ele lidera entra **mesmo sem vínculo**, com
  `member: nil` — a liderança já o coloca no palco, e a função é o que ainda
  falta definir.

  Alimenta a parte somente leitura do próprio perfil (US 1.5): o músico vê onde
  toca e o que faz ali, mas quem muda isso é quem responde pela banda.
  """
  def list_user_bands(%User{} = user), do: list_user_bands(user.id)

  def list_user_bands(user_id) when is_integer(user_id) do
    user_id
    |> List.wrap()
    |> list_bands_by_user()
    |> Map.get(user_id, [])
  end

  @doc """
  O mesmo que `list_user_bands/1`, para várias pessoas de uma vez: devolve um
  mapa de `user_id` para a lista de bandas daquela pessoa, no mesmo formato.

  Existe por causa da lista de pessoas (US 1.8), que mostra as bandas de todo
  mundo na mesma tela — perguntar banda por banda ali seria uma consulta por
  linha. Quem tem uma pessoa só na mão continua chamando `list_user_bands/1`,
  que passa por aqui: a regra do líder sem vínculo é sutil demais para existir
  escrita em dois lugares.

  Quem não toca em banda nenhuma simplesmente não aparece no mapa.
  """
  def list_bands_by_user(user_ids) when is_list(user_ids) do
    memberships =
      from(m in BandMember,
        join: b in assoc(m, :band),
        left_join: i in assoc(m, :instrument),
        where: m.user_id in ^user_ids,
        preload: [band: b, instrument: i]
      )
      |> Repo.all()
      |> Enum.map(
        &{&1.user_id, %{band: &1.band, member: &1, leader?: &1.band.leader_id == &1.user_id}}
      )

    already_member = MapSet.new(memberships, fn {user_id, entry} -> {entry.band.id, user_id} end)

    led_without_membership =
      from(b in Band, where: b.leader_id in ^user_ids)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(already_member, {&1.id, &1.leader_id}))
      |> Enum.map(&{&1.leader_id, %{band: &1, member: nil, leader?: true}})

    (memberships ++ led_without_membership)
    |> Enum.group_by(fn {user_id, _entry} -> user_id end, fn {_user_id, entry} -> entry end)
    |> Map.new(fn {user_id, entries} -> {user_id, Enum.sort_by(entries, & &1.band.name)} end)
  end

  @doc """
  Busca um vínculo pelo id, com músico e banda pré-carregados, ou `nil`.

  Como `get_band/1`, aceita id em string e devolve `nil` para ids inválidos.
  """
  def get_member(id) when is_binary(id), do: RouteId.get(id, &get_member/1)

  def get_member(id) when is_integer(id) do
    BandMember
    |> Repo.get(id)
    |> Repo.preload([:user, :band, :instrument])
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
  Corrige a função de um integrante já vinculado (DT-9).

  Só a função muda: **quem** é o músico e **em qual** banda ele está são
  reafirmados a partir do próprio vínculo, nunca lidos de `attrs`. Trocar de
  músico não é corrigir uma função — seria remover um e adicionar outro, e o
  formulário não tem por que abrir essa porta.

  O changeset é o mesmo de `add_member/3`, então a troca de instrumentista para
  vocalista continua zerando o campo do tipo abandonado.

  Quem pode chamar é decidido antes, por `manage_members?/2`.
  """
  def update_member(%BandMember{} = member, attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{"band_id" => member.band_id, "user_id" => member.user_id})

    member
    |> BandMember.changeset(attrs)
    |> Repo.update()
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
  Músicos que ainda podem ser adicionados a `band`: contas já ativas que ainda
  não são integrantes dela.

  Alimenta o dropdown do formulário, então devolve **todo mundo** quando não há
  busca — e o `query` apenas estreita a lista por nome ou e-mail. Estar em
  outra banda não tira ninguém daqui: o mesmo músico toca em quantas bandas
  for, com função própria em cada uma. Já ser integrante desta banda, sim,
  tira — o vínculo é único por banda.

  O Líder de Banda continua na lista enquanto não tiver vínculo: é assim que
  ele ganha a função dele.
  """
  def list_member_candidates(%Band{} = band, query \\ nil) do
    User
    |> where([u], not is_nil(u.confirmed_at))
    |> where(
      [u],
      u.id not in subquery(from m in BandMember, where: m.band_id == ^band.id, select: m.user_id)
    )
    |> User.search(query)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  ## Instrumentos

  @doc """
  O catálogo inteiro — ativos e inativos —, em ordem alfabética que ignora
  maiúsculas, com quantos integrantes tocam cada instrumento em
  `:member_count`.

  A contagem sai do mesmo `left_join` da consulta, e não de uma pergunta por
  linha: é ela que decide se dá para excluir e é ela que escreve a recusa.
  Alimenta a tela de gestão (US 2.8).
  """
  def list_instruments do
    from(i in Instrument,
      left_join: m in assoc(i, :band_members),
      group_by: i.id,
      select: %{i | member_count: count(m.id)}
    )
    |> Repo.all()
    |> sort_by_name()
  end

  @doc """
  Os instrumentos que se pode escolher hoje: os ativos, em ordem alfabética.

  `keep` é o instrumento do vínculo que está sendo corrigido. Quando ele foi
  desativado depois de a pessoa já o tocar, entra na lista mesmo assim, na
  posição alfabética dele — senão abrir a tela de correção e salvar trocaria a
  função de alguém sem que ninguém tivesse pedido. É a mesma ideia que mantém
  o músico já escolhido dentro da lista de candidatos.

  O `keep` entra **na própria consulta**, e não numa filtragem depois: a lista de
  ids existe porque `i.id == ^nil` é proibido no Ecto, e `in ^[]` é a forma
  segura de dizer "ninguém".
  """
  def list_active_instruments(keep \\ nil) do
    keep_ids = if keep, do: [keep.id], else: []

    Instrument
    |> where([i], i.active or i.id in ^keep_ids)
    |> Repo.all()
    |> sort_by_name()
  end

  # A ordem alfabética é decidida **aqui**, e não por um `order_by` no banco.
  #
  # `ORDER BY lower(name)` parece equivalente e não é: quem ordena é a collation
  # do PostgreSQL, que muda com o locale de quem subiu o banco. Numa máquina com
  # pt_BR, "Violão" vem antes de "Violino"; num container sem locale instalado —
  # o do CI, e o da imagem de produção — a comparação vira byte a byte e a ordem
  # se inverte. A mesma lista aparecia em ordens diferentes conforme o ambiente.
  #
  # A chave tira o acento (decompõe em NFD e joga fora as marcas combinantes),
  # que é como um leitor brasileiro lê uma lista: "violao" antes de "violino".
  # Ordenar uma dezena de linhas em memória não custa nada, e o resultado passa
  # a ser o mesmo em todo lugar.
  defp sort_by_name(instruments), do: Enum.sort_by(instruments, &name_sort_key(&1.name))

  defp name_sort_key(name) do
    name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
  end

  @doc """
  Busca um instrumento pelo id, ou `nil`.

  Como `get_band/1`, aceita id em string e devolve `nil` para ids inválidos.
  """
  def get_instrument(id) when is_binary(id), do: RouteId.get(id, &get_instrument/1)

  def get_instrument(id) when is_integer(id), do: Repo.get(Instrument, id)

  @doc """
  Cadastra um instrumento. Nasce ativo.
  """
  def create_instrument(attrs) do
    %Instrument{}
    |> Instrument.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Renomeia um instrumento.

  Vale para todos os integrantes que o tocam de uma vez — não existe versão
  antiga do nome. É o ganho de o instrumento ser dado e não texto: com o texto
  livre da US 1.4, corrigir "Batera" era abrir o vínculo de cada pessoa.
  """
  def update_instrument(%Instrument{} = instrument, attrs) do
    instrument
    |> Instrument.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Aposenta ou traz de volta um instrumento.

  Não passa pelo changeset do formulário: `active` não é campo que se digita, é
  decisão de circulação. Quem já toca o instrumento desativado continua com a
  função dele intacta — some do dropdown, não da história.
  """
  def set_instrument_active(%Instrument{} = instrument, active) when is_boolean(active) do
    instrument
    |> Ecto.Changeset.change(active: active)
    |> Repo.update()
  end

  @doc """
  Exclui um instrumento que ninguém toca.

  Devolve `{:error, {:in_use, count}}` quando há integrantes com ele — a
  contagem é consultada antes, e é ela que produz a mensagem que aponta
  desativar como o caminho. Excluir é para o cadastro errado; desativar é para
  o instrumento que saiu de circulação.
  """
  def delete_instrument(%Instrument{} = instrument) do
    case count_instrument_members(instrument) do
      0 -> Repo.delete(instrument)
      count -> {:error, {:in_use, count}}
    end
  end

  defp count_instrument_members(%Instrument{id: id}) do
    Repo.aggregate(from(m in BandMember, where: m.instrument_id == ^id), :count)
  end

  @doc """
  Changeset para alimentar o formulário de instrumento.
  """
  def change_instrument(%Instrument{} = instrument \\ %Instrument{}, attrs \\ %{}) do
    Instrument.changeset(instrument, attrs)
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

  defp preload_member({:ok, member}), do: {:ok, Repo.preload(member, [:user, :band, :instrument])}
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
