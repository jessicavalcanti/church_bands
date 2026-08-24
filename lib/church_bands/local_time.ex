defmodule ChurchBands.LocalTime do
  @moduledoc """
  A borda entre o instante gravado e a hora que a pessoa lê (US 3.2).

  O sistema grava **sempre em UTC** — `starts_at`, `timestamps`, validade de
  convite e de token de senha. Até a Fase 2 isso bastava, porque nada exibia
  hora: uma data de expiração se compara, não se lê. O calendário é a primeira
  tela que mostra hora de parede, e "19:00" só quer dizer alguma coisa dentro
  de um fuso.

  **Guardar o deslocamento fixo `−03:00` foi recusado.** Ele acerta metade do
  ano e erra a outra: no dia em que o horário de verão voltar a existir, todo
  culto do calendário andaria uma hora sozinho. Por isso o fuso é nome de
  cidade (`America/Sao_Paulo`, em `config`) resolvido por um banco de fusos de
  verdade, que sabe em que data cada regra passou a valer.

  **Este módulo é o único lugar que converte.** Contexto e schema falam sempre
  em `DateTime` UTC; nenhuma LiveView monta data por conta própria. Ter duas
  conversões é ter duas chances de errar o sentido de uma delas — e o erro de
  sinal é invisível na metade do ano em que os dois deslocamentos coincidem.

  Mora em `ChurchBands`, e não em `ChurchBandsWeb`, apesar de a conversão ser
  de apresentação: quem chama `from_local/1` é o `changeset/2` do evento, e o
  núcleo não pode depender da camada web — no Phoenix a seta aponta sempre no
  outro sentido. O que a borda faz é decidir **quando** converter; o **como**
  é conhecimento do domínio, que é onde o fuso da igreja vive.
  """

  @doc """
  O fuso da igreja, lido da configuração.
  """
  def time_zone, do: Application.fetch_env!(:church_bands, :time_zone)

  @doc """
  O instante de agora, em UTC, truncado ao segundo como a coluna.

  Existe para a regra de "não dá para marcar um evento no passado" ter um
  agora só — e para o teste poder comparar com a mesma precisão que o banco
  guarda, sem perder a fronteira por causa de microssegundos.
  """
  def now, do: DateTime.utc_now(:second)

  @doc """
  O instante UTC visto no fuso da igreja.
  """
  def to_local(%DateTime{} = utc), do: DateTime.shift_zone!(utc, time_zone())

  @doc """
  O dia em que aquele instante caiu, para quem está na igreja.

  Existe porque "que dia é este evento" não se responde do `DateTime` UTC: o
  culto das 23h de 31 de agosto está gravado como 1º de setembro em UTC, e
  agrupá-lo pela data crua o jogaria na célula do mês seguinte.
  """
  def to_date(%DateTime{} = utc), do: utc |> to_local() |> DateTime.to_date()

  @doc """
  O dia de hoje no fuso da igreja.

  A grade destaca "hoje", e hoje é o dia de quem olha a tela — não o do
  servidor, que roda em UTC e vira de data três horas antes.
  """
  def today, do: to_date(now())

  @doc """
  O primeiro instante daquele dia na igreja, em UTC.

  É a borda de baixo da faixa que a grade consulta. Passa por `from_local/1`
  como qualquer hora de parede, e por isso herda dele o tratamento das
  madrugadas de virada do horário de verão — inclusive a de 00:00 que, no ano
  em que o relógio adianta à meia-noite, não existe.
  """
  def start_of_day(%Date{} = date), do: from_local(NaiveDateTime.new!(date, ~T[00:00:00]))

  @doc """
  O último instante daquele dia na igreja, em UTC.

  A borda de cima da faixa, e ela é **inclusiva**: `list_events/1` compara com
  `<=`, então o segundo cheio das 23:59:59 é o que faz o evento das 23:59
  entrar no mês em que a pessoa o marcou. A coluna é `:utc_datetime`, truncada
  ao segundo, e não há instante gravável entre esse e a meia-noite seguinte.
  """
  def end_of_day(%Date{} = date), do: from_local(NaiveDateTime.new!(date, ~T[23:59:59]))

  @doc """
  A hora de parede que a pessoa digitou, convertida no instante UTC que ela
  quis dizer.

  Recebe `NaiveDateTime` porque é isso que chega: o campo virtual do
  formulário é `:naive_datetime`, e o `cast/3` já converteu o texto do
  `datetime-local` antes de o changeset chamar aqui.

  **Nem toda hora de parede existe, e algumas existem duas vezes.** Nas
  madrugadas de virada do horário de verão `DateTime.from_naive/3` não devolve
  `{:ok, _}`:

    * na que o relógio **adianta** há uma lacuna — 00:30 simplesmente não
      aconteceu naquela data — e a resposta é `{:gap, antes, depois}`;
    * na que ele **atrasa** há ambiguidade — 23:30 aconteceu duas vezes — e a
      resposta é `{:ambiguous, primeira, segunda}`.

  Os dois se resolvem aqui, sem mensagem nova na tela: a lacuna vira o
  primeiro instante válido **depois** dela, e a ambiguidade vira a **primeira**
  ocorrência. Devolver erro obrigaria o formulário a explicar horário de verão
  para quem só quer marcar um culto, e a escolha errada custa uma hora num dia
  do ano — não a recusa de salvar.
  """
  def from_local(%NaiveDateTime{} = naive) do
    case DateTime.from_naive(naive, time_zone()) do
      {:ok, local} -> to_utc(local)
      {:ambiguous, first, _second} -> to_utc(first)
      {:gap, _before, after_gap} -> to_utc(after_gap)
    end
  end

  defp to_utc(%DateTime{} = local) do
    local
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  @doc """
  O instante UTC escrito em português, no fuso da igreja.

    * `:date` — `"24/08/2026"`
    * `:time` — `"19:00"`
    * `:short` — `"dom, 24/08 · 19:00"`

  Quem escreve é `Calendar.strftime/3`, da biblioteca padrão, com os nomes de
  dia em português passados por opção: o Elixir não traz nomes localizados, e
  uma tabela própria interpolada à mão reescreveria o que ela já faz. Só
  `:short` precisa deles — nenhum dos três formatos escreve o mês por extenso,
  então `:month_names` ficaria de enfeite.
  """
  @dias ~w(seg ter qua qui sex sáb dom)

  def format(%DateTime{} = utc, formato) do
    utc
    |> to_local()
    |> Calendar.strftime(pattern(formato), abbreviated_day_of_week_names: &Enum.at(@dias, &1 - 1))
  end

  defp pattern(:date), do: "%d/%m/%Y"
  defp pattern(:time), do: "%H:%M"
  defp pattern(:short), do: "%a, %d/%m · %H:%M"

  @doc """
  O mês escrito por extenso, em minúsculas — `"agosto de 2026"`.

  Recebe `%Date{}`, e não `%DateTime{}`, porque um mês não é um instante: não
  há o que converter, e pedir um `DateTime` obrigaria quem chama a inventar uma
  hora só para descartá-la. Mora aqui mesmo assim, junto de `format/2`: escrever
  data em português é o que este módulo faz, e a tabela de nomes existir em dois
  lugares é ter dois lugares para divergir.

  Quem escreve é `Calendar.strftime/3`, com os nomes passados por opção — a
  mesma saída que `format/2` usa para os dias da semana. Minúsculo porque é
  assim que se escreve mês em português; quem quiser inicial maiúscula num
  título resolve na tela, com `capitalize`.
  """
  @meses ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  def format_month(%Date{} = date) do
    Calendar.strftime(date, "%B de %Y", month_names: &Enum.at(@meses, &1 - 1))
  end
end
