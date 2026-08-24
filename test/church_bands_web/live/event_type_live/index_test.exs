defmodule ChurchBandsWeb.EventTypeLive.IndexTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Schedule

  # Os três que a migration cadastra, em ordem alfabética. O banco de teste
  # nasce com eles, e é daí que toda contagem desta tela parte.
  @iniciais ["Confraternização", "Culto", "Ensaio"]

  defp tipo_chamado(nome), do: Enum.find(Schedule.list_event_types(), &(&1.name == nome))

  describe "autorização de acesso" do
    test "Pastor gerencia os tipos de evento", %{conn: conn} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/event-types")
      assert has_element?(view, "#new-event-type-button")
    end

    test "Líder de Louvor gerencia os tipos de evento", %{conn: conn} do
      conn = log_in_user(conn, worship_leader_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/event-types")
      assert has_element?(view, "#new-event-type-button")
    end

    test "músico comum tem o acesso negado", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/event-types")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    # Liderar uma banda dá poder sobre o elenco dela e, a partir da US 3.4,
    # sobre o evento dos tipos marcados — nunca sobre a lista de tipos.
    test "Líder de Banda tem o acesso negado", %{conn: conn} do
      leader = member_fixture()
      band_fixture(%{leader: leader})
      conn = log_in_user(conn, leader)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/event-types")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "visitante não autenticado é mandado para o login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} = live(conn, ~p"/event-types")
      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end

    test "o formulário de cadastro tem a mesma recusa da lista", %{conn: conn} do
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/event-types/new")
      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end

    test "o formulário de edição tem a mesma recusa da lista", %{conn: conn} do
      culto = tipo_chamado("Culto")
      conn = log_in_user(conn, member_fixture())

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/event-types/#{culto.id}/edit")

      assert flash["error"] =~ "Você não tem permissão para acessar esta página."
    end
  end

  describe "a lista de tipos" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "os três iniciais aparecem em ordem alfabética", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/event-types")

      posicoes =
        for nome <- @iniciais do
          posicao = :binary.match(html, nome)
          assert posicao != :nomatch, "#{nome} não está na lista"
          posicao
        end

      assert posicoes == Enum.sort(posicoes)
    end

    test "só o ensaio mostra a marcação do Líder de Banda", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types")

      ensaio = tipo_chamado("Ensaio")
      culto = tipo_chamado("Culto")

      assert view |> element("#event-type-band-leader-#{ensaio.id}") |> render() =~
               "Líder pode criar"

      assert view |> element("#event-type-full-access-#{culto.id}") |> render() =~
               "Só acesso total"

      refute has_element?(view, "#event-type-band-leader-#{culto.id}")
    end

    test "a lista vazia diz que não há tipo cadastrado", %{conn: conn} do
      Enum.each(Schedule.list_event_types(), &Schedule.delete_event_type/1)

      {:ok, view, _html} = live(conn, ~p"/event-types")

      assert has_element?(view, "#event-types-empty")
      refute has_element?(view, "#event-types")
    end
  end

  describe "cadastro de tipo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "cadastra e volta para a lista com o tipo novo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types")

      view |> element("#new-event-type-button") |> render_click()
      assert has_element?(view, "#event-type-form")

      view |> form("#event-type-form", event_type: %{name: "Vigília"}) |> render_submit()

      html = render(view)
      assert html =~ "Tipo de evento Vigília cadastrado."
      assert html =~ "Vigília"
      refute has_element?(view, "#event-type-form")
    end

    test "o tipo cadastrado sem a marcação nasce fechado ao Líder de Banda", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      view |> form("#event-type-form", event_type: %{name: "Vigília"}) |> render_submit()

      vigilia = tipo_chamado("Vigília")
      refute vigilia.band_leader_can_create
      assert has_element?(view, "#event-type-full-access-#{vigilia.id}")
    end

    test "cadastra o tipo marcando que o Líder de Banda pode criar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      view
      |> form("#event-type-form", event_type: %{name: "Vigília", band_leader_can_create: true})
      |> render_submit()

      vigilia = tipo_chamado("Vigília")
      assert vigilia.band_leader_can_create

      assert view |> element("#event-type-band-leader-#{vigilia.id}") |> render() =~
               "Líder pode criar"
    end

    test "recusa nome já cadastrado, sem distinguir maiúsculas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      html = view |> form("#event-type-form", event_type: %{name: "culto"}) |> render_submit()

      assert html =~ "já existe um tipo de evento com esse nome"
    end

    test "recusa nome já cadastrado, sem distinguir acento", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      html =
        view
        |> form("#event-type-form", event_type: %{name: "Confraternizacao"})
        |> render_submit()

      assert html =~ "já existe um tipo de evento com esse nome"
    end

    test "recusa nome curto demais", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      html = view |> form("#event-type-form", event_type: %{name: "V"}) |> render_submit()

      assert html =~ "precisa ter entre 2 e 40 caracteres"
    end

    test "recusa nome comprido demais", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      html =
        view
        |> form("#event-type-form", event_type: %{name: String.duplicate("a", 41)})
        |> render_submit()

      assert html =~ "precisa ter entre 2 e 40 caracteres"
    end

    test "o erro aparece enquanto se digita, antes de enviar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      html = view |> form("#event-type-form", event_type: %{name: "V"}) |> render_change()

      assert html =~ "precisa ter entre 2 e 40 caracteres"
    end

    test "cancelar fecha o formulário sem cadastrar nada", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      view |> element("#cancel-event-type-form") |> render_click()

      refute has_element?(view, "#event-type-form")
      assert Enum.map(Schedule.list_event_types(), & &1.name) == @iniciais
    end
  end

  describe "edição de tipo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "renomeia o tipo pela lista", %{conn: conn} do
      culto = tipo_chamado("Culto")

      {:ok, view, _html} = live(conn, ~p"/event-types")
      view |> element("#edit-event-type-#{culto.id}") |> render_click()

      view
      |> form("#event-type-form", event_type: %{name: "Culto de domingo"})
      |> render_submit()

      assert render(view) =~ "Tipo de evento Culto de domingo atualizado."
      assert Schedule.get_event_type(culto.id).name == "Culto de domingo"
    end

    # O índice compara a linha com as outras, e a linha renomeada é ela mesma.
    test "corrigir o acento do próprio tipo é permitido", %{conn: conn} do
      tipo = event_type_fixture(%{name: "Vigilia"})

      {:ok, view, _html} = live(conn, ~p"/event-types/#{tipo.id}/edit")

      view |> form("#event-type-form", event_type: %{name: "Vigília"}) |> render_submit()

      assert render(view) =~ "Tipo de evento Vigília atualizado."
    end

    test "recusa renomear para o nome de outro tipo", %{conn: conn} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/event-types/#{ensaio.id}/edit")

      html = view |> form("#event-type-form", event_type: %{name: "culto"}) |> render_submit()

      assert html =~ "já existe um tipo de evento com esse nome"
    end

    # Sem o `id` no `<input>`, o `for` do rótulo aponta para nada e clicar no
    # texto não marca a caixa — o defeito que o ajuste local do componente
    # corrigiu.
    test "clicar no rótulo marca a caixa: o for do rótulo acha o campo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/event-types/new")

      assert has_element?(
               view,
               "#event-type-form input[type=checkbox]#event_type_band_leader_can_create"
             )

      assert has_element?(view, "#event-type-form label[for=event_type_band_leader_can_create]")
    end

    test "o formulário abre com a marcação que o tipo já tem", %{conn: conn} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/event-types/#{ensaio.id}/edit")

      assert view |> element("#event-type-form input[type=checkbox]") |> render() =~ "checked"
    end

    test "desmarcar tira a marcação da linha", %{conn: conn} do
      ensaio = tipo_chamado("Ensaio")

      {:ok, view, _html} = live(conn, ~p"/event-types/#{ensaio.id}/edit")

      view
      |> form("#event-type-form", event_type: %{band_leader_can_create: false})
      |> render_submit()

      refute Schedule.get_event_type(ensaio.id).band_leader_can_create
      refute has_element?(view, "#event-type-band-leader-#{ensaio.id}")
      assert has_element?(view, "#event-type-full-access-#{ensaio.id}")
    end

    test "marcar põe a marcação na linha", %{conn: conn} do
      culto = tipo_chamado("Culto")

      {:ok, view, _html} = live(conn, ~p"/event-types/#{culto.id}/edit")

      view
      |> form("#event-type-form", event_type: %{band_leader_can_create: true})
      |> render_submit()

      assert Schedule.get_event_type(culto.id).band_leader_can_create

      assert view |> element("#event-type-band-leader-#{culto.id}") |> render() =~
               "Líder pode criar"
    end

    test "tipo inexistente devolve para a lista com o recado", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/event-types", flash: flash}}} =
               live(conn, ~p"/event-types/0/edit")

      assert flash["error"] =~ "Tipo de evento não encontrado."
    end

    # Quem digita na barra de endereços escreve o que quiser, e isso não pode
    # virar página de erro.
    test "id que nem número é devolve para a lista com o mesmo recado", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/event-types", flash: flash}}} =
               live(conn, ~p"/event-types/abc/edit")

      assert flash["error"] =~ "Tipo de evento não encontrado."

      {:ok, view, _html} = live(conn, ~p"/event-types")
      refute has_element?(view, "#event-type-form")
    end
  end

  describe "exclusão de tipo" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, worship_leader_fixture())}

    test "exclui o tipo e ele some da lista", %{conn: conn} do
      tipo = event_type_fixture(%{name: "Vigília"})

      {:ok, view, _html} = live(conn, ~p"/event-types")
      view |> element("#delete-event-type-#{tipo.id}") |> render_click()

      assert render(view) =~ "Tipo de evento Vigília excluído."
      refute has_element?(view, "#delete-event-type-#{tipo.id}")
      assert Schedule.get_event_type(tipo.id) == nil
    end

    test "a exclusão pede confirmação antes de acontecer", %{conn: conn} do
      tipo = event_type_fixture(%{name: "Vigília"})

      {:ok, view, _html} = live(conn, ~p"/event-types")

      assert view |> element("#delete-event-type-#{tipo.id}") |> render() =~
               "Excluir o tipo Vigília?"
    end

    test "excluir o último tipo deixa a lista com o aviso de vazia", %{conn: conn} do
      [ultimo | resto] = Schedule.list_event_types()
      Enum.each(resto, &Schedule.delete_event_type/1)

      {:ok, view, _html} = live(conn, ~p"/event-types")
      view |> element("#delete-event-type-#{ultimo.id}") |> render_click()

      assert has_element?(view, "#event-types-empty")
      refute has_element?(view, "#event-types")
    end

    test "excluir tipo que outra pessoa já excluiu refaz a lista com o recado", %{conn: conn} do
      tipo = event_type_fixture(%{name: "Vigília"})

      {:ok, view, _html} = live(conn, ~p"/event-types")
      {:ok, _tipo} = Schedule.delete_event_type(tipo)

      view |> element("#delete-event-type-#{tipo.id}") |> render_click()

      html = render(view)
      assert html =~ "Tipo de evento não encontrado."
      refute has_element?(view, "#delete-event-type-#{tipo.id}")
    end
  end
end
