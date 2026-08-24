defmodule ChurchBands.ScheduleTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.ScheduleFixtures

  alias ChurchBands.LocalTime
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event
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

  ## Eventos (US 3.2)

  defp daqui_a_dias(dias), do: in_days(dias)

  defp hora_local(utc), do: utc |> LocalTime.to_local() |> DateTime.to_naive()

  defp atributos(extra) do
    Enum.into(extra, %{
      "event_type_id" => tipo_chamado("Culto").id,
      "title" => "Culto da Noite",
      "starts_at_local" => NaiveDateTime.to_string(hora_local(daqui_a_dias(7)))
    })
  end

  describe "create_event/1" do
    test "marca o evento com tipo, título, data, local e observações" do
      assert {:ok, %Event{} = evento} =
               Schedule.create_event(
                 atributos(%{"location" => "Templo sede", "notes" => "Chegar às 18h"})
               )

      assert evento.title == "Culto da Noite"
      assert evento.location == "Templo sede"
      assert evento.notes == "Chegar às 18h"
      assert evento.status == :scheduled
      assert evento.event_type.name == "Culto"
    end

    test "local e observações são opcionais" do
      assert {:ok, evento} = Schedule.create_event(atributos(%{}))

      assert evento.location == nil
      assert evento.notes == nil
    end

    test "grava o instante que a hora de parede quer dizer" do
      local = hora_local(daqui_a_dias(7))

      {:ok, evento} = Schedule.create_event(atributos(%{"starts_at_local" => local}))

      assert hora_local(evento.starts_at) == local
    end

    test "sem tipo não se cria" do
      {:error, changeset} = Schedule.create_event(atributos(%{"event_type_id" => nil}))

      assert errors_on(changeset).event_type_id == ["escolha o tipo do evento"]
    end

    test "sem título não se cria" do
      {:error, changeset} = Schedule.create_event(atributos(%{"title" => ""}))

      assert errors_on(changeset).title == ["informe o título do evento"]
    end

    test "sem data não se cria" do
      {:error, changeset} = Schedule.create_event(atributos(%{"starts_at_local" => ""}))

      assert errors_on(changeset).starts_at_local == ["informe a data e a hora do evento"]
    end

    test "título com menos de 2 caracteres não se cria" do
      {:error, changeset} = Schedule.create_event(atributos(%{"title" => "C"}))

      assert errors_on(changeset).title == ["precisa ter entre 2 e 80 caracteres"]
    end

    test "título com mais de 80 caracteres não se cria" do
      {:error, changeset} =
        Schedule.create_event(atributos(%{"title" => String.duplicate("a", 81)}))

      assert errors_on(changeset).title == ["precisa ter entre 2 e 80 caracteres"]
    end

    test "local com mais de 120 caracteres não se cria" do
      {:error, changeset} =
        Schedule.create_event(atributos(%{"location" => String.duplicate("a", 121)}))

      assert errors_on(changeset).location == ["precisa ter no máximo 120 caracteres"]
    end

    test "os espaços das pontas do título e do local somem" do
      {:ok, evento} =
        Schedule.create_event(
          atributos(%{"title" => "  Culto da Noite  ", "location" => "  Templo sede  "})
        )

      assert evento.title == "Culto da Noite"
      assert evento.location == "Templo sede"
    end

    # Dois cultos podem se chamar igual — e vão se chamar, toda semana. Quem
    # os distingue é a data.
    test "dois eventos podem ter o mesmo título" do
      assert {:ok, _} = Schedule.create_event(atributos(%{}))
      assert {:ok, _} = Schedule.create_event(atributos(%{}))
    end

    test "tipo que não existe não se cria" do
      {:error, changeset} = Schedule.create_event(atributos(%{"event_type_id" => 0}))

      assert errors_on(changeset).event_type_id == ["escolha um tipo de evento que exista"]
    end

    # A fronteira é o instante, e não o dia: as duas metades dela precisam de
    # teste, senão "no passado" viraria "antes de hoje" sem ninguém notar.
    test "um minuto atrás é recusado, no campo que o formulário mostra" do
      passado = hora_local(DateTime.add(LocalTime.now(), -60, :second))

      {:error, changeset} = Schedule.create_event(atributos(%{"starts_at_local" => passado}))

      assert errors_on(changeset).starts_at_local == ["não dá para marcar um evento no passado"]
    end

    test "daqui a uma hora é aceito" do
      futuro = hora_local(DateTime.add(LocalTime.now(), 3600, :second))

      assert {:ok, _evento} = Schedule.create_event(atributos(%{"starts_at_local" => futuro}))
    end
  end

  describe "update_event/2" do
    test "corrige o título" do
      evento = event_fixture()

      {:ok, evento} = Schedule.update_event(evento, %{"title" => "Culto de Domingo"})

      assert evento.title == "Culto de Domingo"
    end

    # Editar o passado é caminho de sucesso, e não furo na regra da criação: é
    # depois do culto que se descobre que o título estava errado.
    test "corrige um evento que já aconteceu, inclusive regravando a data antiga" do
      passado = DateTime.add(LocalTime.now(), -7, :day)
      evento = event_fixture(%{starts_at: passado})

      {:ok, evento} =
        Schedule.update_event(evento, %{
          "title" => "Culto de semana passada",
          "starts_at_local" => NaiveDateTime.to_string(hora_local(passado))
        })

      assert evento.title == "Culto de semana passada"
      assert DateTime.compare(evento.starts_at, DateTime.truncate(passado, :second)) == :eq
    end

    test "muda a data para outro dia futuro" do
      evento = event_fixture()
      nova = hora_local(daqui_a_dias(30))

      {:ok, evento} =
        Schedule.update_event(evento, %{"starts_at_local" => NaiveDateTime.to_string(nova)})

      assert hora_local(evento.starts_at) == nova
    end

    test "salvar sem mexer na data não desloca o horário" do
      evento = event_fixture()
      antes = evento.starts_at

      {:ok, evento} = Schedule.update_event(evento, %{"title" => "Outro título"})

      assert evento.starts_at == antes
    end

    test "o título continua obrigatório na edição" do
      evento = event_fixture()

      {:error, changeset} = Schedule.update_event(evento, %{"title" => ""})

      assert errors_on(changeset).title == ["informe o título do evento"]
    end

    # `status` fica fora dos dois changesets justamente para não poder ser
    # cancelado por parâmetro forjado no formulário.
    test "o status não se muda por parâmetro" do
      evento = event_fixture()

      {:ok, evento} = Schedule.update_event(evento, %{"status" => "cancelled"})

      assert evento.status == :scheduled
    end
  end

  describe "cancel_event/1 e reopen_event/1" do
    test "cancelar troca o status e preserva o evento" do
      evento = event_fixture()

      {:ok, cancelado} = Schedule.cancel_event(evento)

      assert cancelado.status == :cancelled
      assert Schedule.get_event(evento.id).id == evento.id
    end

    test "reabrir devolve o evento a agendado" do
      evento = event_fixture(%{status: :cancelled})

      {:ok, reaberto} = Schedule.reopen_event(evento)

      assert reaberto.status == :scheduled
    end

    test "cancelar um evento que já passou é permitido — é registro" do
      evento = event_fixture(%{starts_at: DateTime.add(LocalTime.now(), -2, :day)})

      assert {:ok, %Event{status: :cancelled}} = Schedule.cancel_event(evento)
    end

    test "o tipo continua carregado depois de cancelar" do
      evento = event_fixture()

      {:ok, cancelado} = Schedule.cancel_event(evento)

      assert cancelado.event_type.name == evento.event_type.name
    end
  end

  describe "delete_event/1" do
    test "exclui o evento" do
      evento = event_fixture()

      assert {:ok, _} = Schedule.delete_event(evento)
      assert Schedule.get_event(evento.id) == nil
    end
  end

  describe "get_event/1" do
    test "encontra o evento com o tipo carregado" do
      evento = event_fixture()

      assert Schedule.get_event(evento.id).event_type.id == evento.event_type_id
    end

    test "aceita o id em texto, que é como ele chega pela rota" do
      evento = event_fixture()

      assert Schedule.get_event(to_string(evento.id)).id == evento.id
    end

    test "id que não existe não encontra nada" do
      assert Schedule.get_event(0) == nil
    end

    test "id que nem número é não encontra nada" do
      assert Schedule.get_event("banana") == nil
    end
  end

  describe "list_events/1" do
    # A faixa que a grade sempre passa, larga o bastante para caber o que cada
    # teste marca. Quem estreita é o teste que fala de estreitar.
    defp faixa_larga, do: [from: daqui_a_dias(-365), to: daqui_a_dias(365)]

    test "a faixa sem evento nenhum é uma lista vazia" do
      assert Schedule.list_events(faixa_larga()) == []
    end

    test "ordena do mais próximo ao mais distante, com o tipo carregado" do
      depois = event_fixture(%{title: "Depois", starts_at: daqui_a_dias(30)})
      antes = event_fixture(%{title: "Antes", starts_at: daqui_a_dias(2)})

      eventos = Schedule.list_events(faixa_larga())

      assert Enum.map(eventos, & &1.id) == [antes.id, depois.id]
      assert Enum.all?(eventos, &is_struct(&1.event_type, EventType))
    end

    test "o passado entra na faixa junto com o futuro" do
      passado = event_fixture(%{starts_at: DateTime.add(LocalTime.now(), -3, :day)})
      futuro = event_fixture()

      assert Enum.map(Schedule.list_events(faixa_larga()), & &1.id) == [passado.id, futuro.id]
    end

    test "`from` corta o que começa antes dela" do
      event_fixture(%{starts_at: daqui_a_dias(2)})
      depois = event_fixture(%{starts_at: daqui_a_dias(30)})

      eventos = Schedule.list_events(from: daqui_a_dias(10), to: daqui_a_dias(365))

      assert Enum.map(eventos, & &1.id) == [depois.id]
    end

    test "`to` corta o que começa depois dela" do
      antes = event_fixture(%{starts_at: daqui_a_dias(2)})
      event_fixture(%{starts_at: daqui_a_dias(30)})

      eventos = Schedule.list_events(from: daqui_a_dias(-365), to: daqui_a_dias(10))

      assert Enum.map(eventos, & &1.id) == [antes.id]
    end

    # As duas bordas entram: é o que faz o evento marcado para o primeiro
    # instante do mês, e o das 23:59 do último dia, caberem na grade.
    test "as duas bordas da faixa são inclusivas" do
      inicio = event_fixture(%{starts_at: daqui_a_dias(2)})
      fim = event_fixture(%{starts_at: daqui_a_dias(10)})

      eventos = Schedule.list_events(from: inicio.starts_at, to: fim.starts_at)

      assert Enum.map(eventos, & &1.id) == [inicio.id, fim.id]
    end

    test "`type_id` deixa só os eventos daquele tipo" do
      vigilia = event_type_fixture(%{name: "Vigília"})
      da_vigilia = event_fixture(%{event_type: vigilia})
      event_fixture()

      eventos = Schedule.list_events(Keyword.put(faixa_larga(), :type_id, vigilia.id))

      assert Enum.map(eventos, & &1.id) == [da_vigilia.id]
    end

    # Exigir a faixa é o que impede que um "listar tudo" reapareça sem querer.
    test "sem a faixa a consulta não acontece" do
      assert_raise KeyError, fn -> Schedule.list_events(type_id: 1) end
    end
  end

  describe "list_event_types/0 com a contagem de eventos" do
    test "o tipo sem evento nenhum conta zero" do
      assert Enum.all?(Schedule.list_event_types(), &(&1.event_count == 0))
    end

    test "conta os eventos de cada tipo numa consulta só" do
      culto = tipo_chamado("Culto")
      ensaio = tipo_chamado("Ensaio")
      event_fixture(%{event_type: culto})
      event_fixture(%{event_type: culto})
      event_fixture(%{event_type: ensaio})

      contagens =
        Schedule.list_event_types()
        |> Map.new(&{&1.name, &1.event_count})

      assert contagens["Culto"] == 2
      assert contagens["Ensaio"] == 1
      assert contagens["Confraternização"] == 0
    end

    test "a contagem não muda a ordem alfabética" do
      event_fixture(%{event_type: tipo_chamado("Ensaio")})

      assert Enum.map(Schedule.list_event_types(), & &1.name) == @iniciais
    end
  end

  describe "delete_event_type/1 com a trava de tipo em uso" do
    test "tipo com um evento recusa com a contagem no singular" do
      vigilia = event_type_fixture(%{name: "Vigília"})
      event_fixture(%{event_type: vigilia})

      assert Schedule.delete_event_type(vigilia) == {:error, {:in_use, 1}}
      assert Schedule.get_event_type(vigilia.id)
    end

    test "tipo com vários eventos recusa com a contagem deles" do
      culto = tipo_chamado("Culto")
      for _ <- 1..3, do: event_fixture(%{event_type: culto})

      assert Schedule.delete_event_type(culto) == {:error, {:in_use, 3}}
    end

    test "o tipo que nenhum evento usa continua sendo excluído" do
      vigilia = event_type_fixture(%{name: "Vigília"})

      assert {:ok, _} = Schedule.delete_event_type(vigilia)
    end

    test "excluir o evento libera o tipo" do
      vigilia = event_type_fixture(%{name: "Vigília"})
      evento = event_fixture(%{event_type: vigilia})

      {:ok, _} = Schedule.delete_event(evento)

      assert {:ok, _} = Schedule.delete_event_type(vigilia)
    end
  end

  describe "change_event/2" do
    test "o evento novo usa o changeset que recusa data no passado" do
      passado = hora_local(DateTime.add(LocalTime.now(), -60, :second))

      changeset = Schedule.change_event(%Event{}, atributos(%{"starts_at_local" => passado}))

      assert %{starts_at_local: ["não dá para marcar um evento no passado"]} =
               errors_on(changeset)
    end

    # O formulário em branco não acusa data no passado: sem data digitada não
    # há o que comparar, e a recusa só aparece quando ela chega.
    test "o formulário vazio abre sem a recusa de data no passado" do
      changeset = Schedule.change_event()

      assert %Ecto.Changeset{data: %Event{}} = changeset
      assert errors_on(changeset).starts_at_local == ["informe a data e a hora do evento"]
    end

    # É este preenchimento que faz o `datetime-local` abrir com 19:00, e não
    # com a hora UTC — sem ele, salvar sem mexer deslocaria o horário.
    test "o evento gravado abre com a hora de parede no campo virtual" do
      evento = event_fixture()

      changeset = Schedule.change_event(evento)

      assert changeset.data.starts_at_local == hora_local(evento.starts_at)
    end

    test "o evento gravado usa o changeset de edição, que aceita o passado" do
      evento = event_fixture(%{starts_at: DateTime.add(LocalTime.now(), -7, :day)})
      passado = hora_local(evento.starts_at)

      changeset =
        Schedule.change_event(evento, %{"starts_at_local" => NaiveDateTime.to_string(passado)})

      assert changeset.valid?
    end
  end
end
