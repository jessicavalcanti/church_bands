defmodule ChurchBandsWeb.EventSetLive.ShowTest do
  use ChurchBandsWeb.ConnCase, async: true

  import ChurchBands.AccountsFixtures
  import ChurchBands.BandsFixtures
  import ChurchBands.RepertoireFixtures
  import ChurchBands.ScheduleFixtures
  import Phoenix.LiveViewTest

  alias ChurchBands.Schedule

  # O nome da banda é único no sistema (DT-4) e a suíte roda em paralelo: duas
  # "Banda Ebenezer" ao mesmo tempo disputam o índice único. O sufixo mantém o
  # nome legível na asserção e deixa cada teste sozinho com a sua banda.
  defp banda_chamada(nome, attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put(:name, "#{nome} #{System.unique_integer([:positive])}")
    |> band_fixture()
  end

  # A Carla lidera a Ebenezer, que está escalada no "Culto da Noite". É o
  # cenário de quase todo teste desta tela.
  defp cenario(_contexto) do
    carla = member_fixture()
    ebenezer = banda_chamada("Banda Ebenezer", %{leader: carla})
    culto = event_fixture(%{title: "Culto da Noite", starts_at: in_days(7)})
    escala = event_band_fixture(%{event: culto, band: ebenezer})

    %{carla: carla, ebenezer: ebenezer, culto: culto, escala: escala}
  end

  defp caminho(culto, band), do: ~p"/events/#{culto.id}/bands/#{band.id}/set"

  defp no_repertorio(band, titulo, attrs \\ []) do
    attrs
    |> Map.new()
    |> Map.merge(%{band: band, song: song_fixture(title: titulo)})
    |> band_repertoire_fixture()
  end

  defp no_set(escala, band, titulo, position, opts \\ []) do
    {key_da_banda, opts} = Keyword.pop(opts, :key_da_banda, "C")
    entry = no_repertorio(band, titulo, key: key_da_banda)

    event_band_song_fixture(%{
      event_band: escala,
      song: entry.song,
      position: position,
      key: opts[:key]
    })
  end

  # Onde cada texto aparece no HTML: é assim que a suíte confere ordem de lista
  # sem depender de um analisador de DOM.
  defp posicoes(html, textos) do
    Enum.map(textos, fn texto -> html |> :binary.match(texto) |> elem(0) end)
  end

  describe "quem abre a tela" do
    setup [:cenario]

    test "o Líder daquela banda monta o set", %{
      conn: conn,
      carla: carla,
      culto: culto,
      ebenezer: ebenezer
    } do
      {:ok, _view, html} = conn |> log_in_user(carla) |> live(caminho(culto, ebenezer))

      assert html =~ "Set da #{ebenezer.name}"
      assert html =~ "Culto da Noite"
    end

    test "o Pastor monta o set de qualquer banda escalada", %{
      conn: conn,
      culto: culto,
      ebenezer: ebenezer
    } do
      {:ok, _view, html} = conn |> log_in_user(pastor_fixture()) |> live(caminho(culto, ebenezer))

      assert html =~ "Set da #{ebenezer.name}"
    end

    test "o Líder de Louvor também", %{conn: conn, culto: culto, ebenezer: ebenezer} do
      {:ok, _view, html} =
        conn |> log_in_user(worship_leader_fixture()) |> live(caminho(culto, ebenezer))

      assert html =~ "Set da #{ebenezer.name}"
    end

    # A diferença para `manage_event?/2`: lá o assunto é o evento inteiro, e o
    # líder de qualquer banda escalada passa. Aqui o set é de uma banda só.
    test "o Líder de outra banda escalada no mesmo culto é recusado", %{
      conn: conn,
      culto: culto,
      ebenezer: ebenezer
    } do
      outro_lider = member_fixture()
      sion = banda_chamada("Banda Sion", %{leader: outro_lider})
      event_band_fixture(%{event: culto, band: sion})

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               conn |> log_in_user(outro_lider) |> live(caminho(culto, ebenezer))

      assert to == "/events/#{culto.id}"
      assert flash["error"] =~ "Você não tem permissão para montar o set desta banda"
    end

    # Nesta história a tela é de quem monta; a leitura ampla é a US 3.7.
    test "o músico comum da própria banda é recusado", %{
      conn: conn,
      culto: culto,
      ebenezer: ebenezer
    } do
      musico = member_fixture()
      band_member_fixture(%{band: ebenezer, user: musico})

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               conn |> log_in_user(musico) |> live(caminho(culto, ebenezer))

      assert to == "/events/#{culto.id}"
      assert flash["error"] =~ "Você não tem permissão para montar o set desta banda"
    end

    test "a banda não escalada devolve para o evento", %{conn: conn, culto: culto} do
      fora = banda_chamada("Banda Sion")

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               conn |> log_in_user(pastor_fixture()) |> live(caminho(culto, fora))

      assert to == "/events/#{culto.id}"
      assert flash["error"] =~ "Esta banda não está escalada neste evento."
    end

    test "o evento que não existe devolve para o calendário", %{conn: conn, ebenezer: ebenezer} do
      assert {:error, {:redirect, %{to: "/calendar", flash: flash}}} =
               conn
               |> log_in_user(pastor_fixture())
               |> live(~p"/events/999999/bands/#{ebenezer.id}/set")

      assert flash["error"] =~ "Evento não encontrado."
    end

    # O id vem da rota como texto e pode ser qualquer texto: a recusa é a
    # mesma, e não uma página de erro por `Ecto.Query.CastError`.
    test "o id que não é um id cai na mesma recusa", %{conn: conn, culto: culto} do
      conn = log_in_user(conn, pastor_fixture())

      assert {:error, {:redirect, %{to: "/calendar"}}} =
               live(conn, ~p"/events/abc/bands/xyz/set")

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/events/#{culto.id}/bands/xyz/set")
      assert to == "/events/#{culto.id}"
    end

    test "o visitante vai para o login", %{conn: conn, culto: culto, ebenezer: ebenezer} do
      assert {:error, {:redirect, %{to: "/login", flash: flash}}} =
               live(conn, caminho(culto, ebenezer))

      assert flash["error"] =~ "Você precisa entrar para acessar esta página."
    end

    # Corrigir o registro do que foi tocado é útil, e cancelar não é apagar.
    test "o evento cancelado ainda deixa montar o set", %{
      conn: conn,
      carla: carla,
      ebenezer: ebenezer
    } do
      cancelado =
        event_fixture(%{title: "Culto cancelado", starts_at: in_days(7), status: :cancelled})

      event_band_fixture(%{event: cancelado, band: ebenezer})

      {:ok, _view, html} = conn |> log_in_user(carla) |> live(caminho(cancelado, ebenezer))

      assert html =~ "Set da #{ebenezer.name}"
      assert html =~ "Cancelado"
    end

    test "o evento que já passou também", %{conn: conn, carla: carla, ebenezer: ebenezer} do
      passado = event_fixture(%{title: "Culto de ontem", starts_at: in_days(-3)})
      event_band_fixture(%{event: passado, band: ebenezer})

      {:ok, _view, html} = conn |> log_in_user(carla) |> live(caminho(passado, ebenezer))

      assert html =~ "Set da #{ebenezer.name}"
    end
  end

  describe "montar o set" do
    setup [:cenario]

    test "a música do repertório entra no set", %{ebenezer: ebenezer} = ctx do
      %{song: song} = no_repertorio(ebenezer, "Grande é o Senhor")
      view = abrir(ctx)

      html =
        view
        |> form("#add-set-song-form", %{"set_song" => %{"song_id" => song.id}})
        |> render_submit()

      assert html =~ "Grande é o Senhor entrou no set."
      assert has_element?(view, "#set-songs")
      assert html =~ "Grande é o Senhor"
    end

    test "o set vazio diz que está vazio", ctx do
      view = abrir(ctx)

      assert has_element?(view, "#set-empty", "Nenhuma música no set ainda.")
      refute has_element?(view, "#set-songs")
    end

    test "as candidatas são o repertório menos as arquivadas", %{ebenezer: ebenezer} = ctx do
      no_repertorio(ebenezer, "Aleluia")
      no_repertorio(ebenezer, "Santo", status: :archived)

      html = ctx |> abrir() |> render()

      assert html =~ "Aleluia"
      refute html =~ "Santo"
    end

    # Ao contrário de todo outro seletor do sistema: repetir é regra aqui.
    test "a música que já está no set continua sendo oferecida",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      %{song: song} = no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert has_element?(
               abrir(ctx),
               "#add-set-song-form option[value=\"#{song.id}\"]"
             )
    end

    test "a mesma música entra duas vezes, em posições diferentes",
         %{ebenezer: ebenezer, escala: escala} = ctx do
      %{song: song} = no_repertorio(ebenezer, "Grande é o Senhor")
      view = abrir(ctx)

      adicionar = fn ->
        view
        |> form("#add-set-song-form", %{"set_song" => %{"song_id" => song.id}})
        |> render_submit()
      end

      adicionar.()
      adicionar.()

      assert Enum.map(Schedule.list_set(escala), & &1.position) == [1, 2]
    end

    test "as músicas ficam na ordem em que entraram", %{ebenezer: ebenezer} = ctx do
      musicas =
        Enum.map(["Aleluia", "Santo", "Grande é o Senhor"], fn titulo ->
          %{song: song} = no_repertorio(ebenezer, titulo)
          song
        end)

      view = abrir(ctx)

      for song <- musicas do
        view
        |> form("#add-set-song-form", %{"set_song" => %{"song_id" => song.id}})
        |> render_submit()
      end

      [a, b, c] = posicoes(render(view), ["Aleluia", "Santo", "Grande é o Senhor"])

      assert a < b and b < c
    end

    test "a música fora do repertório é recusada, e nada é gravado",
         %{escala: escala} = ctx do
      song = song_fixture(title: "Santo")

      html = ctx |> abrir() |> render_submit("add", %{"set_song" => %{"song_id" => song.id}})

      assert html =~ "Escolha uma música do repertório"
      assert Schedule.list_set(escala) == []
    end

    test "a música arquivada é recusada", %{escala: escala, ebenezer: ebenezer} = ctx do
      %{song: song} = no_repertorio(ebenezer, "Santo", status: :archived)

      html = ctx |> abrir() |> render_submit("add", %{"set_song" => %{"song_id" => song.id}})

      assert html =~ "Escolha uma música do repertório"
      assert Schedule.list_set(escala) == []
    end

    # O catálogo permite dois títulos iguais de propósito (US 2.1): sem o
    # artista no rótulo, as duas linhas do seletor seriam idênticas. O tom
    # entra porque é o que decide entre duas versões da mesma música.
    test "o rótulo da candidata traz artista e tom", %{ebenezer: ebenezer} = ctx do
      band_repertoire_fixture(%{
        band: ebenezer,
        song: song_fixture(%{title: "Grande é o Senhor", artist: "Adhemar de Campos"}),
        key: "D"
      })

      band_repertoire_fixture(%{
        band: ebenezer,
        song: song_fixture(%{title: "Santo"}),
        key: "Em"
      })

      html = ctx |> abrir() |> render()

      assert html =~ "Grande é o Senhor — Adhemar de Campos (D)"
      assert html =~ "Santo (Em)"
    end

    test "o repertório vazio manda montar o repertório antes",
         %{ebenezer: ebenezer} = ctx do
      view = abrir(ctx)

      assert has_element?(view, "#set-no-candidates", "O repertório desta banda está vazio.")

      assert has_element?(
               view,
               "#set-no-candidates a[href=\"/bands/#{ebenezer.id}/repertoire\"]"
             )

      refute has_element?(view, "#add-set-song-form")
    end
  end

  describe "a ordem do set" do
    setup [:cenario]

    test "reordenar grava a nova sequência", %{escala: escala, ebenezer: ebenezer} = ctx do
      primeira = no_set(escala, ebenezer, "Aleluia", 1)
      segunda = no_set(escala, ebenezer, "Santo", 2)
      terceira = no_set(escala, ebenezer, "Grande é o Senhor", 3)

      ids = Enum.map([terceira.id, primeira.id, segunda.id], &to_string/1)
      html = ctx |> abrir() |> render_hook("reorder", %{"ids" => ids})

      [c, a, b] = posicoes(html, ["Grande é o Senhor", "Aleluia", "Santo"])
      assert c < a and a < b

      assert Enum.map(Schedule.list_set(escala), & &1.id) ==
               [terceira.id, primeira.id, segunda.id]
    end

    # O servidor não confia na ordem que chega do navegador.
    test "o id que não é do set é recusado, e nada é gravado",
         %{culto: culto, escala: escala, ebenezer: ebenezer} = ctx do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      alheio = no_set(outra, sion, "Santo", 1)
      minha = no_set(escala, ebenezer, "Aleluia", 1)

      html = ctx |> abrir() |> render_hook("reorder", %{"ids" => [alheio.id, minha.id]})

      assert html =~ "Não foi possível gravar a ordem do set."
      assert Enum.map(Schedule.list_set(escala), &{&1.id, &1.position}) == [{minha.id, 1}]
    end

    test "a lista com um item faltando é recusada",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      primeira = no_set(escala, ebenezer, "Aleluia", 1)
      segunda = no_set(escala, ebenezer, "Santo", 2)

      html = ctx |> abrir() |> render_hook("reorder", %{"ids" => [segunda.id]})

      assert html =~ "Não foi possível gravar a ordem do set."
      assert Enum.map(Schedule.list_set(escala), & &1.id) == [primeira.id, segunda.id]
    end
  end

  describe "o tom de cada linha" do
    setup [:cenario]

    test "sem exceção, mostra o tom da banda", %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D")
      view = abrir(ctx)

      assert has_element?(view, "#set-key-#{item.id}", "D")
      assert has_element?(view, "#set-key-note-#{item.id}", "Tom da banda: D")
    end

    test "o tom deste evento passa a valer, sem esconder o da banda",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D")
      view = abrir(ctx)

      html =
        view
        |> form("#set-key-form-#{item.id}", %{"item_id" => item.id, "key" => "C"})
        |> render_change()

      assert html =~ "Grande é o Senhor fica em C neste evento."
      assert has_element?(view, "#set-key-#{item.id}", "C")
      assert has_element?(view, "#set-key-note-#{item.id}", "a banda toca em D")
    end

    test "limpar o tom volta a herdar o da banda",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D", key: "C")
      view = abrir(ctx)

      html =
        view
        |> form("#set-key-form-#{item.id}", %{"item_id" => item.id, "key" => ""})
        |> render_change()

      assert html =~ "Grande é o Senhor voltou para o tom da banda."
      assert has_element?(view, "#set-key-#{item.id}", "D")
      assert has_element?(view, "#set-key-note-#{item.id}", "Tom da banda: D")
    end

    test "o tom fora dos 24 é recusado", %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1, key_da_banda: "D")

      html =
        ctx |> abrir() |> render_change("update_key", %{"item_id" => item.id, "key" => "H"})

      assert html =~ "Escolha um tom da lista."
      assert [%{key: nil}] = Schedule.list_set(escala)
    end

    # O terceiro caso, que a decisão de apontar para `song_id` cria: a trava de
    # remoção só segura evento futuro.
    test "a música que saiu do repertório mostra travessão e diz por quê",
         %{escala: escala} = ctx do
      song = song_fixture(title: "Grande é o Senhor")
      item = event_band_song_fixture(%{event_band: escala, song: song})
      view = abrir(ctx)

      assert render(view) =~ "—"
      assert has_element?(view, "#set-key-note-#{item.id}", "Fora do repertório da banda")
    end

    test "com tom próprio e sem repertório, a nota diz as duas coisas",
         %{escala: escala} = ctx do
      song = song_fixture(title: "Grande é o Senhor")
      item = event_band_song_fixture(%{event_band: escala, song: song, key: "C"})
      view = abrir(ctx)

      assert has_element?(view, "#set-key-#{item.id}", "C")
      assert has_element?(view, "#set-key-note-#{item.id}", "fora do repertório da banda")
    end

    # O par escala + id é o que faz o id forjado do set de outra banda não
    # casar com nada.
    test "o id de outro set não é encontrado", %{culto: culto} = ctx do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      alheio = no_set(outra, sion, "Santo", 1)

      html =
        ctx |> abrir() |> render_change("update_key", %{"item_id" => alheio.id, "key" => "C"})

      assert html =~ "Música não encontrada neste set."
      assert [%{key: nil}] = Schedule.list_set(outra)
    end
  end

  describe "remover do set" do
    setup [:cenario]

    test "a música sai do set e continua no repertório",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1)

      html = ctx |> abrir() |> element("#remove-set-song-#{item.id}") |> render_click()

      assert html =~ "Grande é o Senhor saiu do set."
      assert Schedule.list_set(escala) == []

      assert Enum.map(Schedule.list_set_candidates(escala), & &1.song.title) ==
               ["Grande é o Senhor"]
    end

    test "a confirmação lembra que a música continua no repertório",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1)

      assert ctx
             |> abrir()
             |> element("#remove-set-song-#{item.id}")
             |> render() =~ "continua no repertório"
    end

    test "o id de outro set não é encontrado", %{culto: culto, escala: escala} = ctx do
      sion = banda_chamada("Banda Sion")
      outra = event_band_fixture(%{event: culto, band: sion})
      alheio = no_set(outra, sion, "Santo", 1)

      html = ctx |> abrir() |> render_click("remove", %{"id" => alheio.id})

      assert html =~ "Música não encontrada neste set."
      assert length(Schedule.list_set(outra)) == 1
      assert Schedule.list_set(escala) == []
    end
  end

  describe "a moldura da tela" do
    setup [:cenario]

    test "o breadcrumb vai do calendário até o set",
         %{culto: culto, ebenezer: ebenezer} = ctx do
      view = abrir(ctx)
      html = render(view)

      assert html =~ "Culto da Noite"
      assert html =~ ebenezer.name
      assert has_element?(view, "a[href=\"/events/#{culto.id}\"]")
    end

    test "há como voltar para o evento e chegar ao repertório",
         %{culto: culto, ebenezer: ebenezer} = ctx do
      view = abrir(ctx)

      assert has_element?(view, "#back-to-event[href=\"/events/#{culto.id}\"]")

      assert has_element?(
               view,
               "#set-band-repertoire[href=\"/bands/#{ebenezer.id}/repertoire\"]"
             )
    end

    test "cada linha do set é arrastável", %{escala: escala, ebenezer: ebenezer} = ctx do
      item = no_set(escala, ebenezer, "Grande é o Senhor", 1)
      view = abrir(ctx)

      assert has_element?(view, "#set-songs[phx-hook=\"SetOrder\"]")
      assert has_element?(view, "#set-song-#{item.id}[draggable=\"true\"]")
      assert has_element?(view, "#set-song-#{item.id}[data-set-item=\"#{item.id}\"]")
    end

    test "a sequência é numerada de 1 em diante",
         %{escala: escala, ebenezer: ebenezer} = ctx do
      primeira = no_set(escala, ebenezer, "Aleluia", 4)
      segunda = no_set(escala, ebenezer, "Santo", 9)
      view = abrir(ctx)

      assert has_element?(view, "#set-position-#{primeira.id}", "1")
      assert has_element?(view, "#set-position-#{segunda.id}", "2")
    end
  end

  # A tela se abre **depois** que o cenário do teste está montado: a LiveView
  # carrega o set no `mount/3`, e um `setup` que a abrisse antes veria sempre o
  # set vazio que o teste ainda ia preencher.
  defp abrir(%{conn: conn, carla: carla, culto: culto, ebenezer: ebenezer}) do
    {:ok, view, _html} = conn |> log_in_user(carla) |> live(caminho(culto, ebenezer))

    view
  end
end
