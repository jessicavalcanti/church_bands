defmodule ChurchBands.LocalTimeTest do
  use ExUnit.Case, async: true

  alias ChurchBands.LocalTime

  # As duas madrugadas de virada do horário de verão brasileiro. Elas não
  # existem mais na lei, mas continuam na base de fusos — e é por causa delas
  # que o fuso é nome de cidade, e não o deslocamento fixo −03:00.
  @adianta ~N[2017-10-15 00:30:00]
  @atrasa ~N[2018-02-17 23:30:00]

  describe "time_zone/0" do
    test "é o fuso configurado, e não um literal espalhado pelo código" do
      assert LocalTime.time_zone() == Application.fetch_env!(:church_bands, :time_zone)
    end
  end

  describe "now/0" do
    # A coluna é `:utc_datetime`, que não guarda microssegundo. Comparar um
    # agora com microssegundo contra um instante lido do banco erraria a
    # fronteira do "está no passado?" por menos de um segundo.
    test "é UTC truncado ao segundo, como a coluna" do
      now = LocalTime.now()

      assert now.time_zone == "Etc/UTC"
      assert now.microsecond == {0, 0}
    end
  end

  describe "to_local/1" do
    test "traz o instante UTC para o fuso da igreja" do
      utc = DateTime.new!(~D[2026-08-30], ~T[22:00:00], "Etc/UTC")

      local = LocalTime.to_local(utc)

      assert local.time_zone == "America/Sao_Paulo"
      assert NaiveDateTime.to_string(DateTime.to_naive(local)) == "2026-08-30 19:00:00"
    end
  end

  describe "to_date/1" do
    test "é o dia no fuso da igreja, e não o do instante em UTC" do
      # 1º de setembro às 02:00 UTC ainda é 31 de agosto às 23:00 na igreja.
      virada = DateTime.new!(~D[2026-09-01], ~T[02:00:00], "Etc/UTC")

      assert LocalTime.to_date(virada) == ~D[2026-08-31]
    end

    test "o meio do dia cai no dia que se espera" do
      meio_dia = DateTime.new!(~D[2026-08-24], ~T[15:00:00], "Etc/UTC")

      assert LocalTime.to_date(meio_dia) == ~D[2026-08-24]
    end
  end

  describe "today/0" do
    test "é o dia de agora, lido no fuso da igreja" do
      assert LocalTime.today() == LocalTime.to_date(LocalTime.now())
    end
  end

  describe "start_of_day/1 e end_of_day/1" do
    test "a borda de baixo é a meia-noite daquele dia na igreja" do
      assert LocalTime.start_of_day(~D[2026-08-24]) |> LocalTime.to_local() |> DateTime.to_naive() ==
               ~N[2026-08-24 00:00:00]
    end

    test "a borda de cima é o último segundo daquele dia na igreja" do
      assert LocalTime.end_of_day(~D[2026-08-24]) |> LocalTime.to_local() |> DateTime.to_naive() ==
               ~N[2026-08-24 23:59:59]
    end

    test "as duas devolvem instantes em UTC, como o banco guarda" do
      assert LocalTime.start_of_day(~D[2026-08-24]).time_zone == "Etc/UTC"
      assert LocalTime.end_of_day(~D[2026-08-24]).time_zone == "Etc/UTC"
    end

    # O dia inteiro cabe entre as duas, e é isso que a grade consulta.
    test "a borda de baixo vem antes da de cima" do
      dia = ~D[2026-08-24]

      assert DateTime.before?(LocalTime.start_of_day(dia), LocalTime.end_of_day(dia))
    end
  end

  describe "format_month/1" do
    test "escreve o mês por extenso, em português e minúsculo" do
      assert LocalTime.format_month(~D[2026-08-01]) == "agosto de 2026"
    end

    # A tabela de meses é própria, e uma tabela própria pode estar fora de
    # ordem: o teste percorre o ano inteiro para pegar isso.
    test "o ano inteiro sai por extenso" do
      meses = for mes <- 1..12, do: LocalTime.format_month(Date.new!(2026, mes, 1))

      assert meses == [
               "janeiro de 2026",
               "fevereiro de 2026",
               "março de 2026",
               "abril de 2026",
               "maio de 2026",
               "junho de 2026",
               "julho de 2026",
               "agosto de 2026",
               "setembro de 2026",
               "outubro de 2026",
               "novembro de 2026",
               "dezembro de 2026"
             ]
    end

    test "o dia do mês não aparece" do
      assert LocalTime.format_month(~D[2026-08-24]) == "agosto de 2026"
    end
  end

  describe "from_local/1" do
    test "converte a hora de parede no instante UTC que ela quer dizer" do
      assert LocalTime.from_local(~N[2026-08-30 19:00:00]) ==
               DateTime.new!(~D[2026-08-30], ~T[22:00:00], "Etc/UTC")
    end

    test "devolve UTC truncado ao segundo" do
      utc = LocalTime.from_local(~N[2026-08-30 19:00:00])

      assert utc.microsecond == {0, 0}
    end

    # É este o teste que pega o deslocamento silencioso: converter para lá e
    # para cá tem de devolver a mesma hora que a pessoa digitou. Com o sinal
    # trocado o horário andaria seis horas, e metade do ano ninguém veria.
    test "ida e volta devolve a mesma hora de parede" do
      digitada = ~N[2026-08-30 19:00:00]

      assert digitada
             |> LocalTime.from_local()
             |> LocalTime.to_local()
             |> DateTime.to_naive() == digitada
    end

    # 15/10/2017 às 00:30 não aconteceu: o relógio pulou de 00:00 para 01:00.
    test "hora de parede que não existiu vira o primeiro instante depois da lacuna" do
      assert {:gap, _antes, _depois} = DateTime.from_naive(@adianta, LocalTime.time_zone())

      assert @adianta
             |> LocalTime.from_local()
             |> LocalTime.to_local()
             |> DateTime.to_naive() == ~N[2017-10-15 01:00:00]
    end

    # 17/02/2018 às 23:30 aconteceu duas vezes, uma em cada deslocamento. A
    # escolha é a primeira, e o que importa é que ela seja sempre a mesma.
    test "hora de parede que aconteceu duas vezes vira a primeira ocorrência" do
      assert {:ambiguous, primeira, _segunda} =
               DateTime.from_naive(@atrasa, LocalTime.time_zone())

      assert LocalTime.from_local(@atrasa) ==
               primeira |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
    end
  end

  describe "format/2" do
    setup do
      %{utc: DateTime.new!(~D[2026-08-30], ~T[22:00:00], "Etc/UTC")}
    end

    test "escreve a data no fuso da igreja", %{utc: utc} do
      assert LocalTime.format(utc, :date) == "30/08/2026"
    end

    test "escreve a hora no fuso da igreja", %{utc: utc} do
      assert LocalTime.format(utc, :time) == "19:00"
    end

    test "o formato curto traz o dia da semana em português", %{utc: utc} do
      assert LocalTime.format(utc, :short) == "dom, 30/08 · 19:00"
    end

    # A abreviação vem de uma lista própria, e uma lista própria pode estar
    # fora de ordem: o teste percorre a semana inteira para pegar isso.
    test "a semana inteira sai abreviada em português" do
      # 24/08/2026 é uma segunda-feira; cada dia às 12h locais, longe da virada.
      dias =
        for offset <- 0..6 do
          ~D[2026-08-24]
          |> Date.add(offset)
          |> DateTime.new!(~T[15:00:00], "Etc/UTC")
          |> LocalTime.format(:short)
          |> String.split(",")
          |> hd()
        end

      assert dias == ~w(seg ter qua qui sex sáb dom)
    end
  end
end
