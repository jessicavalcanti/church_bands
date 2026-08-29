defmodule ChurchBands.Realtime do
  @moduledoc """
  Os tópicos de PubSub do domínio, e só eles.

  Este módulo não sabe o que aconteceu — não é ele que decide **quando**
  publicar, isso é de cada context, no mesmo lugar em que hoje já dispara
  e-mail e `Notifications.notify/3`. O que ele resolve é só a corda que
  cada string de tópico anda pendurada em dois lugares — quem publica e quem
  assina —, e o mesmo risco de `RouteId`: divergir por um caractere faz a
  mensagem sumir sem erro nenhum, porque `Phoenix.PubSub` não avisa quando o
  tópico não tem ninguém do outro lado.

  ## A mensagem é uma campainha, nunca um envelope

  Nenhuma função de broadcast aqui carrega dado — só o átomo que diz *o que
  mudou*. Quem recebe recarrega chamando a mesma consulta que o `mount` já
  usa (`Notifications.list_for_user/1`, `Schedule.list_set/1`, e por aí vai),
  e é isso, não um capricho, que faz duas coisas de uma vez: mantém a mesma
  fronteira de autorização que a consulta já tinha (`PubSub` não tem controle
  de acesso — quem assina o tópico recebe o que for publicado nele, então um
  payload com o corpo de uma notificação alheia seria vazamento na primeira
  vez que alguém assinasse o tópico errado), e evita a classe de bug do
  payload que chegou desatualizado por uma mensagem perdida ou fora de ordem.

  ## Por que existe um tópico por recurso, e não um só

  `events:{id}`, `bands:{id}` etc. existem porque quem assina só quer saber
  do **seu** evento ou da **sua** banda — a tela do evento 4 não tem por que
  acordar a cada escrita no evento 9. A única exceção de propósito é
  `calendar`, sem id: a grade do mês não é de um evento, é de todos, e por
  isso ouve todo mundo.
  """

  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Schedule.EventBandSong

  @doc "Assina `topic` no processo chamador, se a LiveView já estiver conectada."
  def subscribe(topic) when is_binary(topic),
    do: Phoenix.PubSub.subscribe(ChurchBands.PubSub, topic)

  @doc "Publica `message` (sem dado nenhum — ver moduledoc) para quem assina `topic`."
  def broadcast(topic, message) when is_binary(topic),
    do: Phoenix.PubSub.broadcast(ChurchBands.PubSub, topic, message)

  @doc "O sino e a caixa de trocas de `user` (ou do `user_id`)."
  def notifications_topic(%User{id: id}), do: notifications_topic(id)
  def notifications_topic(user_id) when is_integer(user_id), do: "notifications:user:#{user_id}"

  @doc "O evento em si — status, notas, quem está escalado."
  def event_topic(%Event{id: id}), do: event_topic(id)
  def event_topic(%EventBand{event_id: id}), do: event_topic(id)
  def event_topic(event_id) when is_integer(event_id), do: "events:#{event_id}"

  @doc "O set de uma banda escalada — as músicas, a ordem, o tom de cada uma."
  def event_band_topic(%EventBand{id: id}), do: event_band_topic(id)
  def event_band_topic(%EventBandSong{event_band_id: id}), do: event_band_topic(id)

  def event_band_topic(event_band_id) when is_integer(event_band_id),
    do: "event_bands:#{event_band_id}"

  @doc "A grade mensal inteira — sem id, porque nenhum evento é dono dela sozinho."
  def calendar_topic, do: "calendar"

  @doc "O elenco de uma banda."
  def band_topic(%Band{id: id}), do: band_topic(id)
  def band_topic(%BandMember{band_id: id}), do: band_topic(id)
  def band_topic(band_id) when is_integer(band_id), do: "bands:#{band_id}"

  @doc "O repertório de uma banda."
  def band_repertoire_topic(%Band{id: id}), do: band_repertoire_topic(id)
  def band_repertoire_topic(%BandRepertoire{band_id: id}), do: band_repertoire_topic(id)
  def band_repertoire_topic(band_id) when is_integer(band_id), do: "band_repertoire:#{band_id}"
end
