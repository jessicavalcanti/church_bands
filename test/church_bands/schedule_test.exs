defmodule ChurchBands.ScheduleTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.ScheduleFixtures

  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.EventType

  # Os três que a migration cadastra, em ordem alfabética. O banco de teste
  # nasce com eles, e é daí que toda contagem parte.
  @iniciais ["Confraternização", "Culto", "Ensaio"]

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  describe "list_event_types/0" do
    test "traz os três tipos com que o calendário nasce" do
      assert Enum.map(Schedule.list_event_types(), & &1.name) == @iniciais
    end

    # `ORDER BY` no PostgreSQL depende da collation do banco; a ordem do
    # projeto ignora caixa e acento e é a mesma em todo ambiente.
    test "ordena ignorando maiúscula e acento" do
      event_type_fixture(%{name: "ágape"})
      event_type_fixture(%{name: "Batismo"})
      event_type_fixture(%{name: "Vigília"})

      assert Enum.map(Schedule.list_event_types(), & &1.name) ==
               ["ágape", "Batismo", "Confraternização", "Culto", "Ensaio", "Vigília"]
    end

    test "só o ensaio nasce marcado para o Líder de Banda" do
      marcados =
        Schedule.list_event_types()
        |> Enum.filter(& &1.band_leader_can_create)
        |> Enum.map(& &1.name)

      assert marcados == ["Ensaio"]
    end
  end

  describe "get_event_type/1" do
    test "encontra o tipo pelo id" do
      culto = tipo_chamado("Culto")

      assert Schedule.get_event_type(culto.id).name == "Culto"
    end

    test "aceita o id em texto, que é como ele chega pela rota" do
      culto = tipo_chamado("Culto")

      assert Schedule.get_event_type(to_string(culto.id)).name == "Culto"
    end

    test "id que não existe não encontra nada" do
      assert Schedule.get_event_type(0) == nil
    end

    # Quem digita na barra de endereços escreve o que quiser, e isso não pode
    # virar `Ecto.Query.CastError`.
    test "id que nem número é não encontra nada" do
      assert Schedule.get_event_type("abc") == nil
    end
  end

  describe "create_event_type/1" do
    test "cadastra o tipo com o nome digitado" do
      assert {:ok, tipo} = Schedule.create_event_type(%{name: "Vigília"})
      assert tipo.name == "Vigília"
    end

    test "o tipo nasce fechado ao Líder de Banda quando ninguém diz o contrário" do
      assert {:ok, tipo} = Schedule.create_event_type(%{name: "Vigília"})
      refute tipo.band_leader_can_create
    end

    test "cadastra o tipo que o Líder de Banda pode criar" do
      assert {:ok, tipo} =
               Schedule.create_event_type(%{name: "Vigília", band_leader_can_create: true})

      assert tipo.band_leader_can_create
    end

    test "os espaços das pontas do nome são descartados" do
      assert {:ok, tipo} = Schedule.create_event_type(%{name: "  Vigília  "})
      assert tipo.name == "Vigília"
    end

    test "o nome é obrigatório" do
      assert {:error, changeset} = Schedule.create_event_type(%{name: "   "})
      assert %{name: ["informe o nome do tipo de evento"]} = errors_on(changeset)
    end

    test "recusa nome com menos de duas letras" do
      assert {:error, changeset} = Schedule.create_event_type(%{name: "V"})
      assert %{name: ["precisa ter entre 2 e 40 caracteres"]} = errors_on(changeset)
    end

    test "recusa nome com mais de quarenta letras" do
      assert {:error, changeset} = Schedule.create_event_type(%{name: String.duplicate("a", 41)})
      assert %{name: ["precisa ter entre 2 e 40 caracteres"]} = errors_on(changeset)
    end

    test "aceita o nome no limite de quarenta letras" do
      assert {:ok, tipo} = Schedule.create_event_type(%{name: String.duplicate("a", 40)})
      assert String.length(tipo.name) == 40
    end

    test "recusa nome já cadastrado, sem distinguir maiúsculas" do
      assert {:error, changeset} = Schedule.create_event_type(%{name: "cULTO"})
      assert %{name: ["já existe um tipo de evento com esse nome"]} = errors_on(changeset)
    end

    test "recusa nome já cadastrado, sem distinguir acento" do
      assert {:error, changeset} = Schedule.create_event_type(%{name: "Confraternizacao"})
      assert %{name: ["já existe um tipo de evento com esse nome"]} = errors_on(changeset)
    end
  end

  describe "update_event_type/2" do
    test "renomeia o tipo" do
      tipo = event_type_fixture(%{name: "Vigilia"})

      assert {:ok, tipo} = Schedule.update_event_type(tipo, %{name: "Vigília de oração"})
      assert tipo.name == "Vigília de oração"
    end

    # O índice compara a linha com as outras, e a linha renomeada é ela mesma.
    test "corrigir o acento do próprio tipo não colide consigo mesmo" do
      tipo = event_type_fixture(%{name: "Confraternizacao da juventude"})

      assert {:ok, tipo} =
               Schedule.update_event_type(tipo, %{name: "Confraternização da juventude"})

      assert tipo.name == "Confraternização da juventude"
    end

    test "recusa renomear para o nome de outro tipo" do
      tipo = event_type_fixture(%{name: "Vigília"})

      assert {:error, changeset} = Schedule.update_event_type(tipo, %{name: "culto"})
      assert %{name: ["já existe um tipo de evento com esse nome"]} = errors_on(changeset)
    end

    test "abre o tipo ao Líder de Banda" do
      tipo = event_type_fixture(%{name: "Vigília"})

      assert {:ok, tipo} = Schedule.update_event_type(tipo, %{band_leader_can_create: true})
      assert tipo.band_leader_can_create
    end

    test "fecha ao Líder de Banda o tipo que estava aberto" do
      ensaio = tipo_chamado("Ensaio")

      assert {:ok, ensaio} = Schedule.update_event_type(ensaio, %{band_leader_can_create: false})
      refute ensaio.band_leader_can_create
    end
  end

  describe "delete_event_type/1" do
    test "exclui o tipo" do
      tipo = event_type_fixture(%{name: "Vigília"})

      assert {:ok, _tipo} = Schedule.delete_event_type(tipo)
      assert Schedule.get_event_type(tipo.id) == nil
    end

    # Nesta história nada segura um tipo: a tabela `events` só nasce na US 3.2,
    # e é com ela que chega a recusa por tipo em uso.
    test "excluir um dos tipos iniciais funciona como excluir qualquer outro" do
      culto = tipo_chamado("Culto")

      assert {:ok, _tipo} = Schedule.delete_event_type(culto)
      assert Enum.map(Schedule.list_event_types(), & &1.name) == ["Confraternização", "Ensaio"]
    end

    test "a lista fica vazia quando o último tipo é excluído" do
      Enum.each(Schedule.list_event_types(), &Schedule.delete_event_type/1)

      assert Schedule.list_event_types() == []
    end
  end

  describe "change_event_type/2" do
    test "devolve o changeset que alimenta o formulário vazio" do
      assert %Ecto.Changeset{data: %EventType{}} = Schedule.change_event_type()
    end

    test "devolve o changeset do tipo que está sendo corrigido" do
      tipo = event_type_fixture(%{name: "Vigília"})

      changeset = Schedule.change_event_type(tipo, %{name: "Vigília de oração"})

      assert changeset.changes.name == "Vigília de oração"
    end
  end
end
