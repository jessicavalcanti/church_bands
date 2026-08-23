defmodule ChurchBands.SortingTest do
  use ExUnit.Case, async: true

  alias ChurchBands.Sorting

  describe "key/1" do
    test "ignora maiúsculas" do
      assert Sorting.key("Bateria") == Sorting.key("bATERIA")
    end

    test "ignora acento" do
      assert Sorting.key("Violão") == Sorting.key("Violao")
      assert Sorting.key("Ângela") == Sorting.key("Angela")
      assert Sorting.key("Percussão") == Sorting.key("percussao")
    end
  end

  describe "by_name/1" do
    # É o caso que a collation do banco errava de duas formas opostas: com
    # locale pt_BR o acento é ignorado e a ordem sai certa; sem locale, o byte
    # do "Â" vale mais que o de qualquer letra sem acento e a Ângela vai parar
    # depois do Zeca. Comparar codepoints em Elixir tem o mesmo defeito.
    test "o nome acentuado fica no lugar em que se lê, não no fim da lista" do
      pessoas = Enum.map(~w(Zeca André Ângela Bruno Óscar Ivo), &%{name: &1})

      assert Enum.map(Sorting.by_name(pessoas), & &1.name) ==
               ~w(André Ângela Bruno Ivo Óscar Zeca)
    end

    test "ordena sem distinguir maiúsculas" do
      nomes = Enum.map(~w(banda Alfa ZETA), &%{name: &1})

      assert Enum.map(Sorting.by_name(nomes), & &1.name) == ~w(Alfa banda ZETA)
    end

    test "lista vazia continua vazia" do
      assert Sorting.by_name([]) == []
    end
  end
end
