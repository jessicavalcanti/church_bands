defmodule ChurchBands.RateLimit do
  @moduledoc """
  Limite de tentativas por janela de tempo, guardado em ETS.

  Existe para as duas telas públicas que aceitam qualquer requisição que
  chegue: o login, onde tentar sem parar é adivinhar senha, e o "esqueci minha
  senha", onde tentar sem parar transforma a tela num disparador de e-mail
  para qualquer endereço.

  Cada ação é contada em mais de uma chave ao mesmo tempo — o IP de quem pede
  **e** o e-mail pedido —, porque as duas coisas que se quer conter são
  diferentes: um IP martelando muitos e-mails, e muitos IPs martelando um
  e-mail só.

  A janela é fixa: o contador nasce ao ver a primeira tentativa e morre no fim
  da janela, sem deslizar. É o suficiente para o que se está contendo aqui —
  quem esbarrar no limite pode dobrar as tentativas na virada da janela, e
  ainda assim fica ordens de grandeza longe de uma força bruta.

  O contador vive só na memória desta máquina: reiniciar a aplicação zera os
  limites, e uma segunda máquina contaria por conta própria. É a troca
  consciente por não ter dependência nova em pé — para o tamanho de um grupo de
  louvor de igreja, um `:ets` local é a ferramenta certa.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(5)

  @doc """
  Registra uma tentativa de `action` em cada uma das `keys` e diz se ela pode
  seguir.

  `keys` é uma lista de `{nome, valor}` — `[ip: {127, 0, 0, 1}, email: "a@b.c"]`.
  Todas são contadas, mesmo que a primeira já tenha estourado: o limite de uma
  chave não pode esconder o de outra da contagem.

  Devolve `:ok` enquanto todas estiverem dentro do limite e
  `{:error, :rate_limited}` assim que qualquer uma passar dele.
  """
  def hit(action, keys) do
    keys
    |> Enum.map(fn {name, value} -> count(action, {name, value}) end)
    |> Enum.find(:ok, &(&1 != :ok))
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # `:public` porque quem conta é o processo da requisição, não este: o
    # GenServer existe para ser dono da tabela e para varrê-la, e ficaria no
    # caminho se cada tentativa tivesse de passar por ele.
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    # Contador de janela vencida não conta mais nada. Sem a varredura, a tabela
    # guardaria para sempre uma linha por IP e por e-mail vistos desde o boot.
    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", System.system_time(:millisecond)}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  # Uma linha por chave e por janela: `{{ação, chave, janela}, tentativas, fim}`.
  # `update_counter/4` cria a linha zerada e soma na mesma passada, então duas
  # requisições simultâneas não têm como perder uma contagem entre a leitura e a
  # escrita.
  defp count(action, key) do
    {limit, window_ms} = settings(action)
    now = System.system_time(:millisecond)
    window = div(now, window_ms)
    counter = {action, key, window}

    case :ets.update_counter(@table, counter, {2, 1}, {counter, 0, (window + 1) * window_ms}) do
      attempts when attempts <= limit -> :ok
      _attempts -> {:error, :rate_limited}
    end
  end

  defp settings(action) do
    settings =
      :church_bands
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(action)

    {Keyword.fetch!(settings, :limit), Keyword.fetch!(settings, :window_ms)}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
