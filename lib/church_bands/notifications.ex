defmodule ChurchBands.Notifications do
  @moduledoc """
  A central de notificações (US 4.5): o que aconteceu com você, dentro da
  plataforma.

  Até aqui o sistema só sabia falar por e-mail — `Accounts.InviteNotifier`,
  `Accounts.PasswordResetNotifier` e `Swaps.SwapNotifier` —, e quem estava
  logado não tinha onde ver que alguém pediu troca com ele. **A central não
  substitui o e-mail**: quem não abre o sistema todo dia continua sabendo pela
  caixa de entrada, e é por isso que os dois saem juntos, do mesmo ponto do
  `Swaps`.

  ## A seta aponta para cá, e não daqui

  Este contexto **não conhece a troca**. Ele não sabe o que é um pedido, um
  aceite ou uma recusa: o que ele recebe é *para quem, de que tipo, título,
  texto e para onde leva*, já escrito. Quem sabe montar essas frases é quem
  produziu o fato — `Swaps` —, e é ele que chama `notify/3`. É o mesmo sentido
  de seta da US 4.2, e é o que faz o segundo emissor não precisar mexer aqui.

  ## O recorte é a consulta, e não um `if` depois

  Toda função recebe o usuário e filtra por ele **dentro** da consulta. É o que
  faz o id de outra pessoa e o id inventado darem na mesma recusa em
  `get_for_user/2`: dizer <q>existe, mas não é sua</q> já contaria alguma coisa
  sobre a vida de terceiros. Mesma escolha de `Swaps.list_sent/1` e
  `list_received/1` — nem acesso total vê o que não é dele.

  ## O contador é do carregamento da página

  `unread_count/1` roda em toda tela do portal, por dois caminhos —
  `ChurchBandsWeb.UnreadNotifications` nas telas de controller e
  `ChurchBandsWeb.AuthHooks` nas LiveViews. Notificação que aparece sozinha na
  tela pediria PubSub, com assinatura, reconexão e teste de concorrência —
  trabalho que não muda o que a pessoa faz numa escala combinada com semanas de
  antecedência. Uma notificação que chegar com a tela aberta aparece na próxima
  navegação.
  """
  import Ecto.Query

  alias ChurchBands.Accounts.User
  alias ChurchBands.LocalTime
  alias ChurchBands.Notifications.Notification
  alias ChurchBands.Repo
  alias ChurchBands.RouteId

  @doc """
  Grava uma notificação para `user`.

  É por onde **todo** emissor passa. `attrs` traz `:title`, `:body` e `:path` —
  as três coisas que a linha guarda e nunca recalcula.

  **Nunca dentro de transação.** Notificar é anunciar, e não se anuncia o que um
  `rollback` ainda pode desfazer — a mesma regra do e-mail em
  `Swaps.request_swap/4`.
  """
  def notify(%User{} = user, kind, %{title: title, body: body, path: path}) do
    %Notification{}
    |> Notification.changeset(%{
      user_id: user.id,
      kind: kind,
      title: title,
      body: body,
      path: path
    })
    |> Repo.insert()
  end

  @doc """
  As notificações de `user`, da mais recente para a mais antiga.

  Numa consulta só, e sem paginar: são poucas por pessoa numa igreja, e paginar
  acrescentaria ramos que nenhum cenário real exercita. Quem quer só as
  primeiras chama `list_recent/2`.
  """
  def list_for_user(%User{} = user), do: Repo.all(most_recent_first(user))

  @doc """
  As `limit` notificações mais recentes de `user`, na mesma ordem de
  `list_for_user/1`.

  É o resumo que a home mostra (US 4.6), e não a lista: a central continua em
  `/notifications`, e é para lá que o **Ver todas** aponta. As duas leem a
  mesma consulta — `most_recent_first/1` —, e é isso que faz o topo do resumo
  ser sempre o topo da central. Escritas separadas discordariam no dia em que
  o desempate mudasse de lado.

  **Uma consulta**, com o corte feito no banco: a home de quem tem trinta
  notificações carrega cinco linhas, e não trinta para jogar vinte e cinco
  fora.
  """
  def list_recent(%User{} = user, limit) when is_integer(limit) do
    user
    |> most_recent_first()
    |> limit(^limit)
    |> Repo.all()
  end

  # Da mais recente para a mais antiga. O desempate por `id` é o de sempre —
  # duas notificações do mesmo segundo precisam de uma ordem estável para a
  # lista não dançar entre um carregamento e outro.
  defp most_recent_first(%User{} = user) do
    Notification
    |> where([n], n.user_id == ^user.id)
    |> order_by([n], desc: n.inserted_at, desc: n.id)
  end

  @doc """
  Quantas notificações de `user` ainda não foram lidas.

  **Quem não está logado tem zero, e sem consulta nenhuma**: a vitrine pública
  de `/` passa por aqui em toda visita, e perguntar ao banco o que não depende
  do banco seria cobrar de quem nem entrou.
  """
  def unread_count(nil), do: 0

  def unread_count(%User{} = user) do
    Notification
    |> where([n], n.user_id == ^user.id and is_nil(n.read_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  A notificação de `id` que pertence a `user`, ou `nil`.

  **O dono entra na consulta**, e não num `if` depois: é isso que faz o id de
  outra pessoa e o id inventado terminarem na mesma recusa. O id chega da tela
  como texto — quem dispara o evento pelo socket escreve o que quiser —, e por
  isso passa por `ChurchBands.RouteId`.
  """
  def get_for_user(%User{} = user, id) when is_binary(id),
    do: RouteId.get(id, &get_for_user(user, &1))

  def get_for_user(%User{} = user, id) when is_integer(id),
    do: Repo.get_by(Notification, id: id, user_id: user.id)

  @doc """
  Marca `notification` como lida, e devolve a notificação.

  Duas cláusulas para três situações, porque duas delas são a mesma coisa para
  quem lê: **nada muda**. A primeira grava `read_at` na notificação que é de
  `user` e ainda não foi lida; a segunda pega o resto — a que já estava lida,
  que é o clique repetido da regra 14, e a que é de outra pessoa, que é a
  reconferência no servidor de quem chegou aqui por fora da tela.

  O casamento de `user_id` nas duas pontas do padrão é o que dispensa um `if`:
  ou a notificação é dela e está por ler, ou não há o que fazer.
  """
  def mark_read(%User{id: user_id}, %Notification{user_id: user_id, read_at: nil} = notification) do
    {:ok, notification} =
      notification
      |> Ecto.Changeset.change(read_at: LocalTime.now())
      |> Repo.update()

    notification
  end

  def mark_read(%User{}, %Notification{} = notification), do: notification

  @doc """
  Marca como lidas todas as notificações de `user` que ainda não foram.

  Um `update_all` sobre o índice parcial das não lidas: quem tem trinta lidas e
  duas por ler escreve em duas linhas.

  `updated_at` vai escrito à mão porque `update_all` não passa pelos
  `timestamps` do schema — sem ele, a linha marcada aqui e a marcada por
  `mark_read/2` ficariam com formatos diferentes de história.
  """
  def mark_all_read(%User{} = user) do
    now = LocalTime.now()

    Notification
    |> where([n], n.user_id == ^user.id and is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now, updated_at: now])

    :ok
  end
end
