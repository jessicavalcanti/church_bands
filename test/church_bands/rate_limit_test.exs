defmodule ChurchBands.RateLimitTest do
  @moduledoc """
  O contador de tentativas por janela.

  Os testes usam a ação `:login` com chaves inéditas a cada caso — a tabela é
  uma só para a suíte inteira, e chave própria é o que os mantém `async: true`.
  """
  use ExUnit.Case, async: true

  alias ChurchBands.RateLimit

  @limit Application.compile_env!(:church_bands, ChurchBands.RateLimit)[:login][:limit]

  defp unique_email, do: "tentativa#{System.unique_integer([:positive])}@exemplo.com"
  defp unique_ip, do: {10, 0, 0, System.unique_integer([:positive])}

  describe "hit/2" do
    test "deixa passar até o limite e recusa a partir dali" do
      email = unique_email()

      for _ <- 1..@limit do
        assert RateLimit.hit(:login, email: email) == :ok
      end

      assert RateLimit.hit(:login, email: email) == {:error, :rate_limited}
      assert RateLimit.hit(:login, email: email) == {:error, :rate_limited}
    end

    test "o limite de uma chave não alcança a outra" do
      email = unique_email()

      for _ <- 1..(@limit + 1), do: RateLimit.hit(:login, email: email)

      assert RateLimit.hit(:login, email: unique_email()) == :ok
    end

    test "recusa quando qualquer uma das chaves estourou" do
      email = unique_email()

      for _ <- 1..(@limit + 1), do: RateLimit.hit(:login, email: email)

      assert RateLimit.hit(:login, ip: unique_ip(), email: email) ==
               {:error, :rate_limited}
    end

    test "conta todas as chaves, mesmo a tentativa que já foi recusada" do
      email = unique_email()
      ip = unique_ip()

      for _ <- 1..(@limit + 1), do: RateLimit.hit(:login, email: email)

      # Recusada pelo e-mail — e ainda assim o IP saiu dela contado uma vez.
      assert RateLimit.hit(:login, email: email, ip: ip) == {:error, :rate_limited}

      for _ <- 2..@limit do
        assert RateLimit.hit(:login, ip: ip) == :ok
      end

      assert RateLimit.hit(:login, ip: ip) == {:error, :rate_limited}
    end
  end

  describe "varredura" do
    test "apaga o contador da janela vencida e mantém o da janela em curso" do
      # A linha vencida é montada à mão porque não há como esperar uma janela
      # de verdade virar dentro de um teste: o formato é o mesmo que
      # `hit/2` grava — `{{ação, chave, janela}, tentativas, fim da janela}`.
      vencido = {:login, {:email, unique_email()}, 0}
      :ets.insert(RateLimit, {vencido, 1, 0})

      email = unique_email()
      assert RateLimit.hit(:login, email: email) == :ok

      send(RateLimit, :sweep)
      # `:sys.get_state/1` só responde depois de o GenServer ter tratado a
      # mensagem anterior, então aqui a varredura já aconteceu.
      :sys.get_state(RateLimit)

      assert :ets.lookup(RateLimit, vencido) == []
      assert [_em_curso] = :ets.match_object(RateLimit, {{:login, {:email, email}, :_}, :_, :_})
    end
  end
end
