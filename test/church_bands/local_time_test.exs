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
