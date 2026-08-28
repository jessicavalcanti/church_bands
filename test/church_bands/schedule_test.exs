defmodule ChurchBands.ScheduleTest do
  use ChurchBands.DataCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import ChurchBands.ScheduleFixtures

  alias ChurchBands.LocalTime
  alias ChurchBands.Repertoire.Song
  alias ChurchBands.Schedule
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Schedule.EventType

  # Os três que a migration cadastra, em ordem alfabética. O banco de teste
  # nasce com eles, e é daí que toda contagem parte.
  @iniciais ["Confraternização", "Culto", "Ensaio"]

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  # O nome da banda é único no sistema (DT-4) e a suíte roda em paralelo: dois
  # testes criando "Banda Ebenezer" ao mesmo tempo disputam o índice único, e
  # já travaram um no outro. O sufixo mantém o nome legível na asserção e
  # deixa cada teste sozinho com a sua banda.
  defp banda_chamada(nome, attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # Um instante futuro qualquer, no minuto cheio, do qual as horas da janela de
  # conflito são contadas. Sai de `in_days/1` para nascer no futuro, que é o
  # que a criação de evento exige.
  defp base, do: in_days(7)

  defp evento_em(instante, attrs \\ %{}) do
    attrs |> Map.new() |> Map.put(:starts_at, instante) |> event_fixture()
  end

  defp horas(instante, horas), do: DateTime.add(instante, horas * 60 * 60, :second)

  # Um evento com uma banda já escalada. A escala vai pelo fixture, direto ao
  # repositório: montar a agenda de alguém não é o mesmo assunto que a janela
  # de conflito, e passar por ela obrigaria cada cenário a espaçar os eventos.
  defp escalado_em(band, instante, attrs) do
    evento = evento_em(instante, attrs)
    event_band_fixture(%{event: evento, band: band})
    evento
  end

  defp campo_de_data(utc) do
    utc |> LocalTime.to_local() |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()
  end

  ## Apoio do set (US 3.6)

  # O cenário que todas as histórias do set compartilham: a Carla lidera a
  # Ebenezer, que está escalada no "Culto da Noite". O set se pendura na
  # escala, e é ela — e não o evento — que as funções recebem.
  defp cenario_de_set(_contexto) do
    carla = member_fixture()
    ebenezer = banda_chamada("Banda Ebenezer", %{leader: carla})
    culto = evento_em(in_days(7), %{title: "Culto da Noite"})
    escala = event_band_fixture(%{event: culto, band: ebenezer})

    %{carla: carla, ebenezer: ebenezer, culto: culto, escala: escala}
  end

  # Uma música do catálogo no repertório da banda. Devolve o vínculo, de onde
  # saem tanto a música quanto o tom.
  defp no_repertorio(band, titulo, attrs \\ []) do
    attrs
    |> Map.new()
    |> Map.merge(%{band: band, song: song_fixture(title: titulo)})
    |> band_repertoire_fixture()
  end

  # Uma música no repertório **e** no set, que é o estado normal de um item.
  # `key_da_banda` é o tom do repertório; `key`, a exceção deste evento.
  defp musica_no_set(event_band, band, titulo, position, opts \\ []) do
    {key_da_banda, opts} = Keyword.pop(opts, :key_da_banda, "C")
    entry = no_repertorio(band, titulo, key: key_da_banda)

    event_band_song_fixture(%{
      event_band: event_band,
      song: entry.song,
      position: position,
      key: opts[:key]
    })
  end

  # A mesma música no set de outro evento daquela banda. Devolve a música, que
  # é o que a trava do repertório recebe.
  defp no_set_de(evento, band, song) do
    event_band = Schedule.get_event_band(evento.id, band.id)
    event_band_song_fixture(%{event_band: event_band, song: song})

    song
  end

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

  describe "schedule_band/2" do
    test "escala a banda e devolve a linha com a banda carregada" do
      evento = event_fixture()
      banda = banda_chamada("Banda Ebenezer")

      assert {:ok, escala} = Schedule.schedule_band(evento, banda.id)
      assert escala.event_id == evento.id
      assert escala.band.name == banda.name
    end

    test "a mesma banda duas vezes no mesmo evento é recusada" do
      evento = event_fixture()
      banda = band_fixture()
      event_band_fixture(%{event: evento, band: banda})

      assert {:error, changeset} = Schedule.schedule_band(evento, banda.id)
      assert "esta banda já está escalada neste evento" in errors_on(changeset).event_id
    end

    test "banda que não existe é recusada" do
      assert {:error, changeset} = Schedule.schedule_band(event_fixture(), 999_999)

      assert errors_on(changeset).band != []
    end

    test "sem banda nenhuma é recusada" do
      assert {:error, changeset} = Schedule.schedule_band(event_fixture(), nil)

      assert errors_on(changeset).band_id == ["escolha a banda"]
    end

    # O id vem do formulário e pode ser qualquer texto. Perguntar pela janela
    # de conflito com "banana" na mão estouraria um `Ecto.Query.CastError`.
    test "id de banda que nem número é recusado sem estourar" do
      assert {:error, changeset} = Schedule.schedule_band(event_fixture(), "banana")

      assert errors_on(changeset).band_id != []
    end
  end

  describe "a janela de conflito de #{Schedule.conflict_window_hours()} horas" do
    setup do
      %{banda: banda_chamada("Banda Ebenezer"), inicio: base()}
    end

    test "a janela é de três horas", %{} do
      assert Schedule.conflict_window_hours() == 3
    end

    test "escalar dentro da janela é recusado nomeando o outro evento", %{
      banda: banda,
      inicio: inicio
    } do
      culto = evento_em(inicio, %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})
      ensaio = evento_em(horas(inicio, 1))

      assert {:error, {:conflict, outro}} = Schedule.schedule_band(ensaio, banda.id)
      assert outro.title == "Culto da Noite"
    end

    # Os dois cultos de domingo, 9h e 19h: dez horas de distância, e a mesma
    # banda toca nos dois.
    test "escalar fora da janela é permitido", %{banda: banda, inicio: inicio} do
      manha = evento_em(inicio)
      event_band_fixture(%{event: manha, band: banda})
      noite = evento_em(horas(inicio, 10))

      assert {:ok, _escala} = Schedule.schedule_band(noite, banda.id)
    end

    # A borda é aberta: exatamente três horas passa. Fechá-la recusaria o
    # ensaio que começa quando o culto anterior já acabou.
    test "exatamente três horas de distância é permitido", %{banda: banda, inicio: inicio} do
      culto = evento_em(inicio)
      event_band_fixture(%{event: culto, band: banda})
      ensaio = evento_em(horas(inicio, Schedule.conflict_window_hours()))

      assert {:ok, _escala} = Schedule.schedule_band(ensaio, banda.id)
    end

    test "um minuto antes das três horas é recusado", %{banda: banda, inicio: inicio} do
      culto = evento_em(inicio)
      event_band_fixture(%{event: culto, band: banda})
      ensaio = evento_em(DateTime.add(horas(inicio, Schedule.conflict_window_hours()), -60))

      assert {:error, {:conflict, _outro}} = Schedule.schedule_band(ensaio, banda.id)
    end

    test "evento cancelado não ocupa a banda", %{banda: banda, inicio: inicio} do
      cancelado = evento_em(inicio, %{status: :cancelled})
      event_band_fixture(%{event: cancelado, band: banda})
      outro = evento_em(horas(inicio, 1))

      assert {:ok, _escala} = Schedule.schedule_band(outro, banda.id)
    end

    test "duas bandas diferentes no mesmo horário não conflitam", %{inicio: inicio} do
      culto = evento_em(inicio)
      event_band_fixture(%{event: culto, band: band_fixture()})
      outro = evento_em(inicio)

      assert {:ok, _escala} = Schedule.schedule_band(outro, band_fixture().id)
    end
  end

  describe "list_event_bands/1" do
    test "traz as bandas escaladas em ordem alfabética, ignorando acento" do
      evento = event_fixture()

      for nome <- ["Sion", "ágape", "Ebenezer"] do
        event_band_fixture(%{event: evento, band: banda_chamada(nome)})
      end

      assert Schedule.list_event_bands(evento)
             |> Enum.map(&String.first(&1.band.name)) == ["á", "E", "S"]
    end

    test "o evento sem escala devolve lista vazia" do
      assert Schedule.list_event_bands(event_fixture()) == []
    end

    test "não traz a escala de outro evento" do
      evento = event_fixture()
      event_band_fixture(%{event: event_fixture(), band: band_fixture()})

      assert Schedule.list_event_bands(evento) == []
    end
  end

  describe "list_schedulable_bands/1" do
    test "esconde as bandas que já estão escaladas" do
      evento = event_fixture()
      escalada = banda_chamada("Banda Ebenezer")
      livre = banda_chamada("Banda Sion")
      event_band_fixture(%{event: evento, band: escalada})

      assert Enum.map(Schedule.list_schedulable_bands(evento), & &1.name) == [livre.name]
    end

    test "sem escala nenhuma, todas as bandas são candidatas" do
      evento = event_fixture()
      sion = banda_chamada("Banda Sion")
      agape = banda_chamada("ágape")

      assert Enum.map(Schedule.list_schedulable_bands(evento), & &1.name) ==
               [agape.name, sion.name]
    end
  end

  describe "get_event_band/2" do
    test "acha a escala pelo par evento e banda" do
      evento = event_fixture()
      banda = banda_chamada("Banda Ebenezer")
      event_band_fixture(%{event: evento, band: banda})

      assert %{band: encontrada} = Schedule.get_event_band(evento.id, banda.id)
      assert encontrada.id == banda.id
    end

    # É o par que se procura, e não o id da linha: a escala da mesma banda em
    # outro evento não pode ser apagada pela tela deste.
    test "não acha a escala da mesma banda em outro evento" do
      banda = band_fixture()
      event_band_fixture(%{event: event_fixture(), band: banda})

      assert Schedule.get_event_band(event_fixture().id, banda.id) == nil
    end

    test "id de banda que nem número é devolve nil" do
      assert Schedule.get_event_band(event_fixture().id, "banana") == nil
    end
  end

  describe "unschedule_band/1" do
    test "tira a banda da escala sem tocar no evento" do
      evento = event_fixture()
      escala = event_band_fixture(%{event: evento, band: band_fixture()})

      assert {:ok, _escala} = Schedule.unschedule_band(escala)
      assert Schedule.list_event_bands(evento) == []
      assert Schedule.get_event(evento.id)
    end
  end

  describe "update_event/2 reconfere a janela" do
    setup do
      inicio = base()
      banda = banda_chamada("Banda Ebenezer")
      culto = evento_em(inicio, %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})

      ensaio = evento_em(horas(inicio, 10))
      event_band_fixture(%{event: ensaio, band: banda})

      %{banda: banda, culto: culto, ensaio: ensaio, inicio: inicio}
    end

    test "mudar a data para dentro da janela é recusado nomeando banda e evento", %{
      banda: banda,
      ensaio: ensaio,
      inicio: inicio
    } do
      attrs = %{"starts_at_local" => campo_de_data(horas(inicio, 1))}

      assert {:error, {:conflict, em_choque, outro}} = Schedule.update_event(ensaio, attrs)
      assert em_choque.name == banda.name
      assert outro.title == "Culto da Noite"
      assert Schedule.get_event(ensaio.id).starts_at == ensaio.starts_at
    end

    test "mudar a data para fora da janela é gravado", %{ensaio: ensaio, inicio: inicio} do
      attrs = %{"starts_at_local" => campo_de_data(horas(inicio, 20))}

      assert {:ok, atualizado} = Schedule.update_event(ensaio, attrs)
      assert atualizado.starts_at == horas(inicio, 20)
    end

    # A data não mudou, então não há janela a reconferir — e reconferi-la
    # acharia o próprio evento se ele não fosse excluído da consulta.
    test "corrigir só o título de um evento com escala é gravado", %{ensaio: ensaio} do
      assert {:ok, atualizado} = Schedule.update_event(ensaio, %{"title" => "Ensaio geral"})
      assert atualizado.title == "Ensaio geral"
    end

    # Sem isto, quem apagasse o título e mudasse a data receberia "conflito de
    # horário" em vez da mensagem do campo que ela precisa preencher.
    test "formulário inválido devolve o changeset, e não o conflito", %{
      ensaio: ensaio,
      inicio: inicio
    } do
      attrs = %{"title" => "", "starts_at_local" => campo_de_data(horas(inicio, 1))}

      assert {:error, changeset} = Schedule.update_event(ensaio, attrs)
      assert errors_on(changeset).title == ["informe o título do evento"]
    end
  end

  describe "reopen_event/1 reconfere a janela" do
    test "reabrir com a banda ocupada é recusado, e o evento continua cancelado" do
      inicio = base()
      banda = banda_chamada("Banda Ebenezer")

      culto = evento_em(inicio, %{title: "Culto da Noite", status: :cancelled})
      event_band_fixture(%{event: culto, band: banda})

      outro = evento_em(horas(inicio, 1), %{title: "Ensaio geral"})
      event_band_fixture(%{event: outro, band: banda})

      assert {:error, {:conflict, banda_em_choque, evento_em_choque}} =
               Schedule.reopen_event(culto)

      assert banda_em_choque.name == banda.name
      assert evento_em_choque.title == "Ensaio geral"
      assert Schedule.get_event(culto.id).status == :cancelled
    end

    test "reabrir sem choque devolve o evento a agendado" do
      culto = evento_em(base(), %{status: :cancelled})
      event_band_fixture(%{event: culto, band: band_fixture()})

      assert {:ok, reaberto} = Schedule.reopen_event(culto)
      assert reaberto.status == :scheduled
    end
  end

  describe "delete_event/1 com banda escalada" do
    test "o evento com escala não se exclui, e a recusa diz quantas bandas são" do
      evento = event_fixture()
      event_band_fixture(%{event: evento, band: band_fixture()})
      event_band_fixture(%{event: evento, band: band_fixture()})

      assert {:error, {:scheduled, 2}} = Schedule.delete_event(evento)
      assert Schedule.get_event(evento.id)
    end

    test "o evento sem escala continua sendo excluído" do
      evento = event_fixture()

      assert {:ok, _evento} = Schedule.delete_event(evento)
      assert Schedule.get_event(evento.id) == nil
    end
  end

  describe "create_event_with_band/2" do
    setup do
      lider = member_fixture()
      banda = banda_chamada("Banda Ebenezer", %{leader: lider})

      # Tipos próprios, e não os três da migration: criar um evento segura a
      # linha do tipo pela chave estrangeira, e a suíte tem um teste que esvazia
      # a tabela de tipos inteira. Além disso o teste passa a dizer o que
      # importa — *marcado* e *não marcado* —, e não um nome de tipo.
      %{
        lider: lider,
        banda: banda,
        ensaio: event_type_fixture(%{band_leader_can_create: true}),
        culto: event_type_fixture(%{})
      }
    end

    defp attrs_de_ensaio(tipo, banda, extra \\ %{}) do
      Enum.into(extra, %{
        "event_type_id" => tipo.id,
        "band_id" => banda.id,
        "title" => "Ensaio da semana",
        "starts_at_local" => campo_de_data(base())
      })
    end

    test "cria o evento com a banda já escalada", %{lider: lider, banda: banda, ensaio: ensaio} do
      attrs = attrs_de_ensaio(ensaio, banda)

      assert {:ok, evento} = Schedule.create_event_with_band(attrs, lider)
      assert evento.event_type_id == ensaio.id
      assert [escala] = Schedule.list_event_bands(evento)
      assert escala.band.name == banda.name
    end

    test "o tipo que o líder não pode marcar é recusado", %{
      lider: lider,
      banda: banda,
      culto: culto
    } do
      attrs = attrs_de_ensaio(culto, banda)

      assert {:error, :unauthorized_type} = Schedule.create_event_with_band(attrs, lider)
      assert Repo.all(Event) == []
    end

    # A função é o caminho do **líder**, e por isso a banda tem de ser dele:
    # quem tem acesso total não passa por aqui — a tela o manda para
    # `create_event/1` e ele escala as bandas depois.
    test "a banda que o líder não lidera é recusada", %{lider: lider, ensaio: ensaio} do
      attrs = attrs_de_ensaio(ensaio, band_fixture())

      assert {:error, :unauthorized_band} = Schedule.create_event_with_band(attrs, lider)
      assert Repo.all(Event) == []
    end

    test "sem banda nenhuma é recusado", %{lider: lider, banda: banda, ensaio: ensaio} do
      attrs = attrs_de_ensaio(ensaio, banda, %{"band_id" => ""})

      assert {:error, :unauthorized_band} = Schedule.create_event_with_band(attrs, lider)
    end

    # O tipo ausente não é recusa de permissão: quem o recusa é o changeset,
    # com a mensagem que aparece no campo.
    test "sem tipo nenhum devolve o changeset, e não a recusa de permissão", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio
    } do
      attrs = attrs_de_ensaio(ensaio, banda, %{"event_type_id" => ""})

      assert {:error, changeset} = Schedule.create_event_with_band(attrs, lider)
      assert errors_on(changeset).event_type_id == ["escolha o tipo do evento"]
    end

    # É o que a transação existe para garantir: sem ela, o evento ficaria
    # gravado e a escala não, e o ensaio nasceria fora do alcance de quem o
    # criou.
    test "evento inválido não grava nem o evento nem a escala", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio
    } do
      attrs = attrs_de_ensaio(ensaio, banda, %{"title" => ""})

      assert {:error, changeset} = Schedule.create_event_with_band(attrs, lider)
      assert errors_on(changeset).title == ["informe o título do evento"]
      assert Repo.all(Event) == []
      assert Repo.all(EventBand) == []
    end

    test "marcar no passado é recusado, como em qualquer criação", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio
    } do
      ontem = campo_de_data(DateTime.add(LocalTime.now(), -1, :day))
      attrs = attrs_de_ensaio(ensaio, banda, %{"starts_at_local" => ontem})

      assert {:error, changeset} = Schedule.create_event_with_band(attrs, lider)
      assert errors_on(changeset).starts_at_local == ["não dá para marcar um evento no passado"]
    end

    test "o ensaio dentro da janela de um culto da banda é recusado inteiro", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio
    } do
      inicio = base()
      culto = evento_em(inicio, %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: banda})

      attrs =
        attrs_de_ensaio(ensaio, banda, %{"starts_at_local" => campo_de_data(horas(inicio, 1))})

      assert {:error, {:conflict, outro}} = Schedule.create_event_with_band(attrs, lider)
      assert outro.title == "Culto da Noite"
      assert Enum.map(Repo.all(Event), & &1.id) == [culto.id]
    end
  end

  describe "manage_event?/2" do
    setup do
      lider = member_fixture()
      banda = band_fixture(%{leader: lider})
      # Tipo próprio, e não o "Ensaio" da migration: um destes testes o
      # desmarca, e mexer na linha que a suíte inteira lê poria os testes para
      # esperar uns pelos outros.
      tipo = event_type_fixture(%{band_leader_can_create: true})
      ensaio = event_fixture(%{event_type: tipo})

      %{lider: lider, banda: banda, ensaio: ensaio, tipo: tipo}
    end

    test "quem tem acesso total gerencia qualquer evento", %{ensaio: ensaio} do
      assert Schedule.manage_event?(pastor_fixture(), ensaio)
      assert Schedule.manage_event?(worship_leader_fixture(), ensaio)
    end

    test "o líder gerencia o evento de tipo marcado em que a banda dele está", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio
    } do
      event_band_fixture(%{event: ensaio, band: banda})

      assert Schedule.manage_event?(lider, ensaio)
    end

    test "desescalar a banda tira o evento das mãos do líder", %{lider: lider, ensaio: ensaio} do
      refute Schedule.manage_event?(lider, ensaio)
    end

    test "desmarcar o tipo tira o evento das mãos do líder", %{
      lider: lider,
      banda: banda,
      ensaio: ensaio,
      tipo: tipo
    } do
      event_band_fixture(%{event: ensaio, band: banda})
      {:ok, _tipo} = Schedule.update_event_type(tipo, %{band_leader_can_create: false})

      refute Schedule.manage_event?(lider, Schedule.get_event(ensaio.id))
    end

    test "o líder de outra banda não gerencia o ensaio desta", %{banda: banda, ensaio: ensaio} do
      event_band_fixture(%{event: ensaio, band: banda})
      outro_lider = member_fixture()
      band_fixture(%{leader: outro_lider})

      refute Schedule.manage_event?(outro_lider, ensaio)
    end

    test "músico comum não gerencia evento nenhum", %{banda: banda, ensaio: ensaio} do
      event_band_fixture(%{event: ensaio, band: banda})

      refute Schedule.manage_event?(member_fixture(), ensaio)
    end
  end

  describe "create_event_of_type?/2 e create_events?/1" do
    setup do
      %{
        marcado: event_type_fixture(%{band_leader_can_create: true}),
        solto: event_type_fixture(%{})
      }
    end

    test "quem tem acesso total marca qualquer tipo", %{solto: solto} do
      assert Schedule.create_event_of_type?(pastor_fixture(), solto)
      assert Schedule.create_events?(pastor_fixture())
    end

    test "o líder de banda marca só os tipos marcados", %{marcado: marcado, solto: solto} do
      lider = member_fixture()
      band_fixture(%{leader: lider})

      assert Schedule.create_event_of_type?(lider, marcado)
      refute Schedule.create_event_of_type?(lider, solto)
      assert Schedule.create_events?(lider)
    end

    test "quem não lidera banda nenhuma não marca nada", %{marcado: marcado} do
      musico = member_fixture()

      refute Schedule.create_event_of_type?(musico, marcado)
      refute Schedule.create_events?(musico)
    end
  end

  describe "list_events/1 com filtro por banda" do
    setup do
      inicio = base()
      ebenezer = banda_chamada("Banda Ebenezer")
      sion = banda_chamada("Banda Sion")

      culto = evento_em(inicio, %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: ebenezer})

      ensaio = evento_em(horas(inicio, 24), %{title: "Ensaio da Sion"})
      event_band_fixture(%{event: ensaio, band: sion})

      sem_banda = evento_em(horas(inicio, 48), %{title: "Confraternização"})

      %{
        ebenezer: ebenezer,
        inicio: inicio,
        faixa: [from: DateTime.add(inicio, -1, :day), to: DateTime.add(inicio, 7, :day)],
        sem_banda: sem_banda
      }
    end

    test "traz só os eventos daquela banda", %{ebenezer: ebenezer, faixa: faixa} do
      eventos = Schedule.list_events(Keyword.put(faixa, :band_id, ebenezer.id))

      assert Enum.map(eventos, & &1.title) == ["Culto da Noite"]
    end

    test "sem filtro traz todos, inclusive o que não tem banda", %{faixa: faixa} do
      assert length(Schedule.list_events(faixa)) == 3
    end

    test "as bandas escaladas vêm pré-carregadas em cada evento", %{
      ebenezer: ebenezer,
      faixa: faixa
    } do
      eventos = Schedule.list_events(faixa)
      culto = Enum.find(eventos, &(&1.title == "Culto da Noite"))
      confraternizacao = Enum.find(eventos, &(&1.title == "Confraternização"))

      assert Enum.map(culto.bands, & &1.id) == [ebenezer.id]
      assert confraternizacao.bands == []
    end

    test "o filtro por banda soma ao de tipo", %{ebenezer: ebenezer, faixa: faixa} do
      opts = faixa |> Keyword.put(:band_id, ebenezer.id) |> Keyword.put(:type_id, 999_999)

      assert Schedule.list_events(opts) == []
    end
  end

  describe "list_upcoming_events_for_user/2" do
    setup do
      carla = member_fixture(%{name: "Carla Musicista"})
      ebenezer = banda_chamada("Banda Ebenezer")
      band_member_fixture(%{band: ebenezer, user: carla})

      %{carla: carla, ebenezer: ebenezer}
    end

    test "traz o evento da banda em que a pessoa toca, com a banda nomeada", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})

      assert [evento] = Schedule.list_upcoming_events_for_user(carla)
      assert evento.id == culto.id
      assert Enum.map(evento.event_bands, & &1.band.name) == [ebenezer.name]
    end

    # Liderar sem ser membro é o caso que `Bands.list_user_bands/1` já
    # reconhece, e a subconsulta de ids repete: quem lidera a banda precisa
    # saber onde ela toca, mesmo sem tocar nela.
    test "liderar conta como participar, mesmo sem vínculo de membro" do
      joao = member_fixture(%{name: "João Líder"})
      sion = banda_chamada("Banda Sion", %{leader: joao})
      culto = escalado_em(sion, in_days(3), %{title: "Culto da Manhã"})

      assert [%Event{id: id}] = Schedule.list_upcoming_events_for_user(joao)
      assert id == culto.id
    end

    test "o evento a 40 dias fica de fora", %{carla: carla, ebenezer: ebenezer} do
      escalado_em(ebenezer, in_days(40), %{title: "Vigília de Fim de Ano"})

      assert Schedule.list_upcoming_events_for_user(carla) == []
    end

    test "o evento que já passou fica de fora", %{carla: carla, ebenezer: ebenezer} do
      escalado_em(ebenezer, in_days(-2), %{title: "Culto de Domingo Passado"})

      assert Schedule.list_upcoming_events_for_user(carla) == []
    end

    test "o evento a 29 dias entra", %{carla: carla, ebenezer: ebenezer} do
      culto = escalado_em(ebenezer, in_days(29), %{title: "Culto da Noite"})

      assert [%Event{id: id}] = Schedule.list_upcoming_events_for_user(carla)
      assert id == culto.id
    end

    # A borda é **fechada** nos dois lados, e `:now` existe para ela poder ser
    # verificada ao segundo, sem depender do relógio da máquina.
    test "a borda dos #{Schedule.upcoming_days()} dias é fechada", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      culto = escalado_em(ebenezer, in_days(30), %{title: "Culto da Noite"})
      agora = DateTime.add(culto.starts_at, -Schedule.upcoming_days(), :day)

      assert [%Event{id: id}] = Schedule.list_upcoming_events_for_user(carla, now: agora)
      assert id == culto.id
    end

    test "um segundo além da borda já fica de fora", %{carla: carla, ebenezer: ebenezer} do
      culto = escalado_em(ebenezer, in_days(30), %{title: "Culto da Noite"})

      agora =
        culto.starts_at
        |> DateTime.add(-Schedule.upcoming_days(), :day)
        |> DateTime.add(-1, :second)

      assert Schedule.list_upcoming_events_for_user(carla, now: agora) == []
    end

    test "o culto de uma banda de que não participo não aparece", %{carla: carla} do
      sion = banda_chamada("Banda Sion")
      escalado_em(sion, in_days(3), %{title: "Culto da Sion"})

      assert Schedule.list_upcoming_events_for_user(carla) == []
    end

    test "acesso total vê a igreja inteira, inclusive o evento sem banda escalada", %{
      ebenezer: ebenezer
    } do
      pastor = pastor_fixture()
      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      confraternizacao = evento_em(in_days(4), %{title: "Confraternização"})

      eventos = Schedule.list_upcoming_events_for_user(pastor)

      assert Enum.map(eventos, & &1.id) == [culto.id, confraternizacao.id]
      assert Enum.map(List.last(eventos).event_bands, & &1.band.name) == []
    end

    test "acesso total vê todas as bandas escaladas, e não só as suas", %{ebenezer: ebenezer} do
      sion = banda_chamada("Banda Sion")
      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: sion})

      assert [evento] = Schedule.list_upcoming_events_for_user(worship_leader_fixture())
      assert Enum.map(evento.event_bands, & &1.band.name) == [ebenezer.name, sion.name]
    end

    test "quem está em duas bandas escaladas no mesmo culto vê um item só", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      band_member_fixture(%{band: sion, user: carla})

      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: sion})

      assert [evento] = Schedule.list_upcoming_events_for_user(carla)
      assert evento.id == culto.id
      assert Enum.map(evento.event_bands, & &1.band.name) == [ebenezer.name, sion.name]
    end

    # A escala pré-carregada é a de quem está olhando: a Sion toca no mesmo
    # culto, e quem não é dela não a vê na própria linha.
    test "a escala que vem junto é só a das bandas da pessoa", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: sion})

      assert [evento] = Schedule.list_upcoming_events_for_user(carla)
      assert Enum.map(evento.event_bands, & &1.band.name) == [ebenezer.name]
    end

    test "o evento cancelado continua na lista", %{carla: carla, ebenezer: ebenezer} do
      culto =
        escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite", status: :cancelled})

      assert [%Event{id: id, status: :cancelled}] =
               Schedule.list_upcoming_events_for_user(carla)

      assert id == culto.id
    end

    test "vêm do mais próximo ao mais distante", %{carla: carla, ebenezer: ebenezer} do
      vigilia = escalado_em(ebenezer, in_days(20), %{title: "Vigília"})
      culto = escalado_em(ebenezer, in_days(2), %{title: "Culto da Noite"})
      ensaio = escalado_em(ebenezer, in_days(10), %{title: "Ensaio"})

      assert Enum.map(Schedule.list_upcoming_events_for_user(carla), & &1.id) ==
               [culto.id, ensaio.id, vigilia.id]
    end

    test "quem não está em banda nenhuma não vê evento nenhum", %{ebenezer: ebenezer} do
      escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})

      assert Schedule.list_upcoming_events_for_user(member_fixture()) == []
    end

    test "uma consulta só alimenta o bloco, com vários eventos e várias bandas", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      band_member_fixture(%{band: sion, user: carla})

      culto = escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      event_band_fixture(%{event: culto, band: sion})
      escalado_em(sion, in_days(10), %{title: "Ensaio da Sion"})

      eventos = assert_queries(1, fn -> Schedule.list_upcoming_events_for_user(carla) end)

      assert Enum.map(eventos, &length(&1.event_bands)) == [2, 1]
      # O tipo vem na mesma consulta: a linha escreve o nome dele, e buscá-lo
      # depois seria uma pergunta por evento.
      assert Enum.all?(eventos, &match?(%EventType{}, &1.event_type))
    end

    test "para acesso total também é uma consulta só", %{ebenezer: ebenezer} do
      pastor = pastor_fixture()
      escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      evento_em(in_days(4), %{title: "Confraternização"})

      eventos = assert_queries(1, fn -> Schedule.list_upcoming_events_for_user(pastor) end)

      assert length(eventos) == 2
    end

    ## O evento incluído por id (US 4.4)

    test "o evento de banda alheia entra quando o id é incluído", %{carla: carla} do
      sion = banda_chamada("Banda Sion")
      culto = escalado_em(sion, in_days(3), %{title: "Culto da Manhã"})

      assert Schedule.list_upcoming_events_for_user(carla) == []

      assert [%Event{id: id}] =
               Schedule.list_upcoming_events_for_user(carla, include_event_ids: [culto.id])

      assert id == culto.id
    end

    # A consequência assumida: no evento assumido a escala vem inteira. Quem
    # vai tocar lá precisa ver em que banda vai tocar, e o recorte pelas bandas
    # da pessoa esconderia justamente a banda que interessa.
    test "o evento incluído traz a escala inteira, e não a recortada", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      culto = escalado_em(sion, in_days(3), %{title: "Culto da Manhã"})
      event_band_fixture(%{event: culto, band: ebenezer})

      assert [evento] =
               Schedule.list_upcoming_events_for_user(carla, include_event_ids: [culto.id])

      assert length(evento.event_bands) == 2
    end

    test "o evento incluído fora dos 30 dias continua fora", %{carla: carla} do
      sion = banda_chamada("Banda Sion")
      vigilia = escalado_em(sion, in_days(40), %{title: "Vigília de Fim de Ano"})

      assert Schedule.list_upcoming_events_for_user(carla, include_event_ids: [vigilia.id]) == []
    end

    test "o evento incluído entra na ordem cronológica, sem bloco à parte", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      ensaio = escalado_em(ebenezer, in_days(5), %{title: "Ensaio"})
      assumido = escalado_em(sion, in_days(2), %{title: "Culto da Manhã"})

      eventos =
        Schedule.list_upcoming_events_for_user(carla, include_event_ids: [assumido.id])

      assert Enum.map(eventos, & &1.id) == [assumido.id, ensaio.id]
    end

    test "o evento incluído cancelado continua na lista", %{carla: carla} do
      sion = banda_chamada("Banda Sion")

      culto =
        escalado_em(sion, in_days(3), %{title: "Culto da Manhã", status: :cancelled})

      assert [%Event{status: :cancelled}] =
               Schedule.list_upcoming_events_for_user(carla, include_event_ids: [culto.id])
    end

    # Acesso total já vê a igreja inteira, e a opção não tem o que acrescentar
    # — mas quem passa a lista não sabe quem está do outro lado, então ela
    # precisa atravessar sem mudar resultado nenhum.
    test "acesso total vê o mesmo com e sem ids incluídos", %{ebenezer: ebenezer} do
      pastor = pastor_fixture()
      sion = banda_chamada("Banda Sion")
      escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      culto = escalado_em(sion, in_days(4), %{title: "Culto da Manhã"})
      evento_em(in_days(5), %{title: "Confraternização"})

      sem_ids = Schedule.list_upcoming_events_for_user(pastor)

      com_ids =
        Schedule.list_upcoming_events_for_user(pastor, include_event_ids: [culto.id])

      assert Enum.map(sem_ids, & &1.id) == Enum.map(com_ids, & &1.id)
      assert length(com_ids) == 3
    end

    test "o evento sem banda nenhuma continua fora da agenda de quem só toca", %{carla: carla} do
      evento_em(in_days(4), %{title: "Confraternização"})

      assert Schedule.list_upcoming_events_for_user(carla, include_event_ids: []) == []
    end

    test "com ids incluídos continua sendo uma consulta só", %{
      carla: carla,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      escalado_em(ebenezer, in_days(3), %{title: "Culto da Noite"})
      um = escalado_em(sion, in_days(4), %{title: "Culto da Manhã"})
      outro = escalado_em(sion, in_days(5), %{title: "Ensaio da Sion"})

      eventos =
        assert_queries(1, fn ->
          Schedule.list_upcoming_events_for_user(carla, include_event_ids: [um.id, outro.id])
        end)

      assert length(eventos) == 3
    end
  end

  describe "list_set/1" do
    setup [:cenario_de_set]

    test "traz as músicas na ordem de execução", %{escala: escala, ebenezer: ebenezer} do
      terceira = musica_no_set(escala, ebenezer, "Aleluia", 3)
      primeira = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      segunda = musica_no_set(escala, ebenezer, "Santo", 2)

      assert Enum.map(Schedule.list_set(escala), & &1.id) ==
               [primeira.id, segunda.id, terceira.id]
    end

    # Duas posições iguais só nascem de uma gravação concorrente, mas a lista
    # não pode mudar de ordem entre dois F5 por causa disso.
    test "desempata por id quando duas posições são iguais", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      primeira = musica_no_set(escala, ebenezer, "Aleluia", 1)
      segunda = musica_no_set(escala, ebenezer, "Santo", 1)

      assert Enum.map(Schedule.list_set(escala), & &1.id) == [primeira.id, segunda.id]
    end

    test "cada item vem com a música e o tom da banda", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D")

      assert [item] = Schedule.list_set(escala)
      assert item.song.title == "Grande é o Senhor"
      assert item.band_key == :D
      assert item.key == nil
    end

    test "o tom deste evento convive com o da banda", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D", key: "C")

      assert [%{key: :C, band_key: :D}] = Schedule.list_set(escala)
    end

    # A trava de remoção só segura evento futuro, então o set de um culto
    # passado alcança este caso — e é dele que sai o <q>—</q> da tela.
    test "a música que saiu do repertório vem sem tom da banda", %{escala: escala} do
      song = song_fixture(title: "Grande é o Senhor")
      event_band_song_fixture(%{event_band: escala, song: song})

      assert [%{band_key: nil, key: nil}] = Schedule.list_set(escala)
    end

    test "é uma consulta só", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      musica_no_set(escala, ebenezer, "Santo", 2)

      itens = assert_queries(1, fn -> Schedule.list_set(escala) end)

      assert length(itens) == 2
      assert Enum.all?(itens, &match?(%Song{}, &1.song))
    end

    test "o set vazio é uma lista vazia", %{escala: escala} do
      assert Schedule.list_set(escala) == []
    end

    test "o set de uma banda não traz o da outra", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      musica_no_set(outra, sion, "Santo", 1)

      assert [%{song: %{title: "Grande é o Senhor"}}] = Schedule.list_set(escala)
    end
  end

  describe "list_set_candidates/1" do
    setup [:cenario_de_set]

    test "oferece o repertório da banda em ordem alfabética", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      no_repertorio(ebenezer, "Santo")
      no_repertorio(ebenezer, "Aleluia")

      assert Enum.map(Schedule.list_set_candidates(escala), & &1.song.title) ==
               ["Aleluia", "Santo"]
    end

    test "em aprendizado e pronta entram", %{escala: escala, ebenezer: ebenezer} do
      no_repertorio(ebenezer, "Aleluia", status: :learning)
      no_repertorio(ebenezer, "Santo", status: :ready)

      assert length(Schedule.list_set_candidates(escala)) == 2
    end

    test "a arquivada fica de fora", %{escala: escala, ebenezer: ebenezer} do
      no_repertorio(ebenezer, "Aleluia")
      no_repertorio(ebenezer, "Santo", status: :archived)

      assert Enum.map(Schedule.list_set_candidates(escala), & &1.song.title) == ["Aleluia"]
    end

    # Ao contrário de todo outro seletor do sistema: repetir é regra aqui.
    test "não esconde o que já está no set", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert Enum.map(Schedule.list_set_candidates(escala), & &1.song.title) ==
               ["Grande é o Senhor"]
    end

    test "o repertório de outra banda não entra", %{escala: escala} do
      no_repertorio(banda_chamada("Banda Sion"), "Santo")

      assert Schedule.list_set_candidates(escala) == []
    end
  end

  describe "add_song_to_set/2" do
    setup [:cenario_de_set]

    test "a música entra no fim da sequência", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Aleluia", 1)
      %{song: song} = no_repertorio(ebenezer, "Santo")

      assert {:ok, item} = Schedule.add_song_to_set(escala, song.id)
      assert item.position == 2
      assert item.song.title == "Santo"
    end

    test "a primeira música do set entra na posição 1", %{escala: escala, ebenezer: ebenezer} do
      %{song: song} = no_repertorio(ebenezer, "Santo")

      assert {:ok, %{position: 1}} = Schedule.add_song_to_set(escala, song.id)
    end

    test "a mesma música entra duas vezes, em posições diferentes", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      %{song: song} = no_repertorio(ebenezer, "Grande é o Senhor")

      assert {:ok, %{position: 1}} = Schedule.add_song_to_set(escala, song.id)
      assert {:ok, %{position: 2}} = Schedule.add_song_to_set(escala, song.id)
      assert length(Schedule.list_set(escala)) == 2
    end

    test "a música fora do repertório da banda é recusada", %{escala: escala} do
      song = song_fixture(title: "Santo")

      assert Schedule.add_song_to_set(escala, song.id) == {:error, :not_in_repertoire}
      assert Schedule.list_set(escala) == []
    end

    test "a música arquivada é recusada", %{escala: escala, ebenezer: ebenezer} do
      %{song: song} = no_repertorio(ebenezer, "Santo", status: :archived)

      assert Schedule.add_song_to_set(escala, song.id) == {:error, :not_in_repertoire}
    end

    test "a música do repertório de outra banda é recusada", %{escala: escala} do
      %{song: song} = no_repertorio(banda_chamada("Banda Sion"), "Santo")

      assert Schedule.add_song_to_set(escala, song.id) == {:error, :not_in_repertoire}
    end

    # O id vem do formulário como texto e pode ser qualquer texto: a recusa é a
    # mesma, e não um `Ecto.Query.CastError`.
    test "o que não é um id é recusado", %{escala: escala} do
      assert Schedule.add_song_to_set(escala, "banana") == {:error, :not_in_repertoire}
      assert Schedule.add_song_to_set(escala, nil) == {:error, :not_in_repertoire}
    end

    test "aceita o id em texto, que é como o formulário o manda", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      %{song: song} = no_repertorio(ebenezer, "Santo")

      assert {:ok, _item} = Schedule.add_song_to_set(escala, to_string(song.id))
    end
  end

  describe "get_set_item/2" do
    setup [:cenario_de_set]

    test "acha a linha do set com a música carregada", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert %{id: id, song: %Song{title: "Grande é o Senhor"}} =
               Schedule.get_set_item(escala, item.id)

      assert id == item.id
    end

    # O par escala + id é o que faz o id forjado do set de outra banda não
    # casar com nada.
    test "não acha a linha do set de outra banda", %{culto: culto, escala: escala} do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      item = musica_no_set(outra, sion, "Santo", 1)

      assert Schedule.get_set_item(escala, item.id) == nil
    end

    test "o que não é um id devolve nil", %{escala: escala} do
      assert Schedule.get_set_item(escala, "banana") == nil
    end
  end

  describe "update_set_item/2" do
    setup [:cenario_de_set]

    test "grava o tom só deste evento", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D")

      assert {:ok, %{key: :C}} = Schedule.update_set_item(item, %{"key" => "C"})
      assert [%{key: :C, band_key: :D}] = Schedule.list_set(escala)
    end

    test "o tom em branco volta a herdar o da banda", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D", key: "C")

      assert {:ok, %{key: nil}} = Schedule.update_set_item(item, %{"key" => ""})
      assert [%{key: nil, band_key: :D}] = Schedule.list_set(escala)
    end

    test "o tom fora dos 24 é recusado", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert {:error, changeset} = Schedule.update_set_item(item, %{"key" => "H"})
      assert %{key: ["is invalid"]} = errors_on(changeset)
    end

    test "não muda a posição nem a música", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      outra = song_fixture(title: "Santo")

      assert {:ok, atualizado} =
               Schedule.update_set_item(item, %{
                 "key" => "C",
                 "position" => 9,
                 "song_id" => outra.id
               })

      assert atualizado.position == 1
      assert atualizado.song_id == item.song_id
    end
  end

  describe "remove_from_set/1" do
    setup [:cenario_de_set]

    test "tira a música do set sem mexer no repertório", %{escala: escala, ebenezer: ebenezer} do
      item = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert {:ok, _item} = Schedule.remove_from_set(item)
      assert Schedule.list_set(escala) == []

      assert Enum.map(Schedule.list_set_candidates(escala), & &1.song.title) ==
               ["Grande é o Senhor"]
    end
  end

  describe "reorder_set/2" do
    setup [:cenario_de_set]

    test "regrava as posições na ordem recebida", %{escala: escala, ebenezer: ebenezer} do
      primeira = musica_no_set(escala, ebenezer, "Aleluia", 1)
      segunda = musica_no_set(escala, ebenezer, "Santo", 2)
      terceira = musica_no_set(escala, ebenezer, "Grande é o Senhor", 3)

      assert Schedule.reorder_set(escala, [terceira.id, primeira.id, segunda.id]) == :ok

      assert Enum.map(Schedule.list_set(escala), &{&1.id, &1.position}) ==
               [{terceira.id, 1}, {primeira.id, 2}, {segunda.id, 3}]
    end

    # A lista chega do hook de arraste, como texto.
    test "aceita os ids em texto", %{escala: escala, ebenezer: ebenezer} do
      primeira = musica_no_set(escala, ebenezer, "Aleluia", 1)
      segunda = musica_no_set(escala, ebenezer, "Santo", 2)

      ids = Enum.map([segunda.id, primeira.id], &to_string/1)

      assert Schedule.reorder_set(escala, ids) == :ok
      assert Enum.map(Schedule.list_set(escala), & &1.id) == [segunda.id, primeira.id]
    end

    test "o id que não é do set é recusado, e nada é gravado", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      alheio = musica_no_set(outra, sion, "Santo", 1)
      minha = musica_no_set(escala, ebenezer, "Aleluia", 1)

      assert Schedule.reorder_set(escala, [alheio.id, minha.id]) == {:error, :mismatched_set}
      assert Enum.map(Schedule.list_set(escala), &{&1.id, &1.position}) == [{minha.id, 1}]
    end

    test "a lista com um item faltando é recusada", %{escala: escala, ebenezer: ebenezer} do
      primeira = musica_no_set(escala, ebenezer, "Aleluia", 1)
      segunda = musica_no_set(escala, ebenezer, "Santo", 2)

      assert Schedule.reorder_set(escala, [segunda.id]) == {:error, :mismatched_set}
      assert Enum.map(Schedule.list_set(escala), & &1.id) == [primeira.id, segunda.id]
    end

    # Repetir um id e omitir outro mantém o tamanho da lista, e é o que a
    # comparação ordenada — e não a de tamanho — pega.
    test "a lista com um id repetido é recusada", %{escala: escala, ebenezer: ebenezer} do
      primeira = musica_no_set(escala, ebenezer, "Aleluia", 1)
      musica_no_set(escala, ebenezer, "Santo", 2)

      assert Schedule.reorder_set(escala, [primeira.id, primeira.id]) ==
               {:error, :mismatched_set}
    end

    test "o que não é um id é recusado", %{escala: escala, ebenezer: ebenezer} do
      musica_no_set(escala, ebenezer, "Aleluia", 1)

      assert Schedule.reorder_set(escala, ["banana"]) == {:error, :mismatched_set}
      assert Schedule.reorder_set(escala, [%{}]) == {:error, :mismatched_set}
    end

    test "reordenar o set vazio com a lista vazia não faz nada", %{escala: escala} do
      assert Schedule.reorder_set(escala, []) == :ok
    end
  end

  describe "list_sets_for_event/1" do
    setup [:cenario_de_set]

    test "agrupa o set de cada banda escalada pela escala", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})

      musica_no_set(escala, ebenezer, "Aleluia", 1)
      musica_no_set(escala, ebenezer, "Santo", 2)
      musica_no_set(outra, sion, "Grande é o Senhor", 1)

      sets = Schedule.list_sets_for_event(culto)

      assert Enum.map(sets[escala.id], & &1.song.title) == ["Aleluia", "Santo"]
      assert Enum.map(sets[outra.id], & &1.song.title) == ["Grande é o Senhor"]
    end

    test "cada lista vem na ordem de execução", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      musica_no_set(escala, ebenezer, "Aleluia", 3)
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      musica_no_set(escala, ebenezer, "Santo", 2)

      assert Enum.map(Schedule.list_sets_for_event(culto)[escala.id], & &1.song.title) ==
               ["Grande é o Senhor", "Santo", "Aleluia"]
    end

    test "cada item traz a música e o tom da banda", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      musica_no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D", key: "C")

      assert [%{key: :C, band_key: :D, song: %Song{title: "Grande é o Senhor"}}] =
               Schedule.list_sets_for_event(culto)[escala.id]
    end

    # O mesmo `left_join` de `list_set/1`, e o mesmo terceiro estado: a música
    # saiu do repertório da banda depois de entrar no set.
    test "a música que saiu do repertório vem sem tom da banda", %{
      culto: culto,
      escala: escala
    } do
      event_band_song_fixture(%{event_band: escala, song: song_fixture(title: "Aleluia")})

      assert [%{band_key: nil, key: nil}] = Schedule.list_sets_for_event(culto)[escala.id]
    end

    # É o critério de aceite da tela do evento: perguntar banda a banda seria
    # uma consulta por linha da escala.
    test "é uma consulta só, com várias bandas e vários sets", %{
      culto: culto,
      escala: escala,
      ebenezer: ebenezer
    } do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})

      musica_no_set(escala, ebenezer, "Aleluia", 1)
      musica_no_set(escala, ebenezer, "Santo", 2)
      musica_no_set(outra, sion, "Grande é o Senhor", 1)

      sets = assert_queries(1, fn -> Schedule.list_sets_for_event(culto) end)

      assert Enum.map(sets, fn {_escala, itens} -> length(itens) end) |> Enum.sort() == [1, 2]
    end

    test "a escala sem set nenhum não aparece no mapa", %{culto: culto, escala: escala} do
      assert Schedule.list_sets_for_event(culto) == %{}
      assert Map.get(Schedule.list_sets_for_event(culto), escala.id, []) == []
    end

    test "não traz o set de outro evento", %{culto: culto, ebenezer: ebenezer} do
      outro = evento_em(in_days(9), %{title: "Ensaio"})
      escala_do_outro = event_band_fixture(%{event: outro, band: ebenezer})
      musica_no_set(escala_do_outro, ebenezer, "Santo", 1)

      assert Schedule.list_sets_for_event(culto) == %{}
    end
  end

  describe "future_set_titles/2" do
    setup [:cenario_de_set]

    test "nomeia o evento futuro em que a música está no set", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      %{song: song} = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert Schedule.future_set_titles(ebenezer, song) == ["Culto da Noite"]
    end

    test "vem do mais próximo ao mais distante", %{escala: escala, ebenezer: ebenezer} do
      %{song: song} = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)

      vigilia = escalado_em(ebenezer, in_days(20), %{title: "Vigília"})
      ensaio = escalado_em(ebenezer, in_days(2), %{title: "Ensaio geral"})

      no_set_de(vigilia, ebenezer, song)
      no_set_de(ensaio, ebenezer, song)

      assert Schedule.future_set_titles(ebenezer, song) ==
               ["Ensaio geral", "Culto da Noite", "Vigília"]
    end

    test "o evento que já passou não segura nada", %{ebenezer: ebenezer} do
      passado = escalado_em(ebenezer, in_days(-3), %{title: "Culto de ontem"})
      song = no_set_de(passado, ebenezer, song_fixture(title: "Grande é o Senhor"))

      assert Schedule.future_set_titles(ebenezer, song) == []
    end

    test "o evento cancelado não segura nada", %{ebenezer: ebenezer} do
      cancelado =
        escalado_em(ebenezer, in_days(3), %{title: "Culto cancelado", status: :cancelled})

      song = no_set_de(cancelado, ebenezer, song_fixture(title: "Grande é o Senhor"))

      assert Schedule.future_set_titles(ebenezer, song) == []
    end

    test "o set de outra banda não segura nada", %{culto: culto} do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      %{song: song} = musica_no_set(outra, sion, "Grande é o Senhor", 1)

      assert Schedule.future_set_titles(banda_chamada("Banda Ebenezer"), song) == []
    end

    test "a música que entrou duas vezes no mesmo set nomeia o evento uma vez", %{
      escala: escala,
      ebenezer: ebenezer
    } do
      %{song: song} = musica_no_set(escala, ebenezer, "Grande é o Senhor", 1)
      event_band_song_fixture(%{event_band: escala, song: song, position: 2})

      assert Schedule.future_set_titles(ebenezer, song) == ["Culto da Noite"]
    end

    test "a música que não está em set nenhum devolve lista vazia", %{ebenezer: ebenezer} do
      assert Schedule.future_set_titles(ebenezer, song_fixture()) == []
    end

    # A borda se fixa pelo `:now`, sem depender do relógio da máquina.
    test "o evento que começa exatamente agora ainda segura", %{ebenezer: ebenezer} do
      agora = in_days(1)
      evento = escalado_em(ebenezer, agora, %{title: "Culto de agora"})
      song = no_set_de(evento, ebenezer, song_fixture(title: "Grande é o Senhor"))

      assert Schedule.future_set_titles(ebenezer, song, now: agora) == ["Culto de agora"]
      assert Schedule.future_set_titles(ebenezer, song, now: DateTime.add(agora, 1)) == []
    end
  end

  describe "manage_set?/2" do
    setup [:cenario_de_set]

    test "quem tem acesso total monta o set de qualquer banda", %{escala: escala} do
      assert Schedule.manage_set?(pastor_fixture(), escala)
      assert Schedule.manage_set?(worship_leader_fixture(), escala)
    end

    test "o Líder daquela banda monta o set dela", %{escala: escala, carla: carla} do
      assert Schedule.manage_set?(carla, escala)
    end

    # É a diferença para `manage_event?/2`, que aceita o líder de qualquer
    # banda escalada: lá o assunto é o evento inteiro.
    test "o Líder de outra banda escalada no mesmo culto não monta este set", %{
      culto: culto,
      escala: escala
    } do
      outro_lider = member_fixture()
      sion = banda_chamada("Banda Sion", %{leader: outro_lider})
      event_band_fixture(%{event: culto, band: sion})

      refute Schedule.manage_set?(outro_lider, escala)
    end

    test "o músico da banda não monta o set dela", %{escala: escala, ebenezer: ebenezer} do
      musico = member_fixture()
      band_member_fixture(%{band: ebenezer, user: musico})

      refute Schedule.manage_set?(musico, escala)
    end
  end
end
