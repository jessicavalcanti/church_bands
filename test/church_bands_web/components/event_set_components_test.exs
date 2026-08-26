defmodule ChurchBandsWeb.EventSetComponentsTest do
  @moduledoc """
  A linha do set, compartilhada pela tela do evento e pela tela do set (US 3.7).

  As duas telas já exercitam o componente montado; o que se testa aqui é o que
  elas têm em comum e não deveria depender de nenhuma delas: **qual tom está
  valendo** — os quatro estados dele — e o que `editable` liga e desliga.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.EventSetComponents
  import Phoenix.LiveViewTest

  # Um item de set como as consultas o entregam: a música pré-carregada e
  # `band_key` virtual, vindo do `left_join` com o repertório da banda.
  defp item(attrs \\ []) do
    song =
      struct(
        ChurchBands.Repertoire.Song,
        Keyword.merge(
          [id: 7, title: "Aleluia", artist: nil, chord_chart_url: nil, reference_url: nil],
          Keyword.get(attrs, :song, [])
        )
      )

    struct(ChurchBands.Schedule.EventBandSong,
      id: 42,
      key: Keyword.get(attrs, :key),
      band_key: Keyword.get(attrs, :band_key),
      song: song
    )
  end

  defp linha(item, assigns \\ %{}) do
    render_component(&set_row/1, Map.merge(%{item: item, index: 1}, assigns))
  end

  describe "effective_key/2" do
    test "sem exceção, o tom que vale é o da banda" do
      assert effective_key(%{key: nil}, :D) == {:band, :D}
    end

    test "com exceção, o tom do evento vale e o da banda vem junto para ser sinalizado" do
      assert effective_key(%{key: :C}, :D) == {:event, :C, :D}
    end

    # A música saiu do repertório da banda depois de entrar no set: a trava de
    # remoção só segura evento futuro.
    test "sem exceção e sem repertório, não há tom nenhum" do
      assert effective_key(%{key: nil}, nil) == :orphan
    end

    # O quarto estado, que é o terceiro ramo com o segundo elemento nulo: o
    # item tem tom próprio **e** a música saiu do repertório.
    test "com exceção e sem repertório, o tom do evento vale sozinho" do
      assert effective_key(%{key: :C}, nil) == {:event, :C, nil}
    end
  end

  describe "o tom que a linha mostra" do
    test "herda o do repertório quando não há exceção" do
      html = linha(item(band_key: :D))

      assert html =~ ~s(id="set-key-42")
      assert html =~ ">D<"
      assert html =~ "Tom da banda: D"
    end

    test "mostra o deste evento e diz em que tom a banda toca" do
      html = linha(item(key: :C, band_key: :D))

      assert html =~ ">C<"
      assert html =~ "Só deste evento · a banda toca em D"
    end

    test "mostra travessão quando a música saiu do repertório da banda" do
      html = linha(item())

      assert html =~ "—"
      assert html =~ "Fora do repertório da banda"
    end

    test "com tom próprio e fora do repertório, a nota diz as duas coisas" do
      html = linha(item(key: :C))

      assert html =~ ">C<"
      assert html =~ "Só deste evento · fora do repertório da banda"
    end
  end

  describe "os links da música" do
    test "cifra e referência abrem em nova aba" do
      html =
        linha(
          item(
            song: [
              chord_chart_url: "https://cifras.example/aleluia",
              reference_url: "https://video.example/aleluia"
            ]
          )
        )

      assert html =~ ~s(href="https://cifras.example/aleluia")
      assert html =~ ~s(href="https://video.example/aleluia")
      assert html =~ ~s(target="_blank")
    end

    # Nem um traço: música sem link não ganha lugar guardado na linha.
    test "sem link nenhum, a linha não mostra nada no lugar deles" do
      html = linha(item())

      refute html =~ "set-chord-chart-42"
      refute html =~ "set-reference-42"
    end
  end

  describe "editable" do
    test "ligado, a linha tem alça, seletor de tom e botão de remover" do
      html =
        linha(item(band_key: :C), %{
          editable: true,
          key_options: [{"C", "C"}, {"D", "D"}],
          band_name: "Banda Ebenezer"
        })

      assert html =~ ~s(draggable="true")
      assert html =~ ~s(id="set-event-key-42")
      assert html =~ ~s(id="remove-set-song-42")
      assert html =~ "Ela continua no repertório da Banda Ebenezer."
    end

    test "desligado, a linha é só leitura" do
      html = linha(item(band_key: :C))

      refute html =~ "draggable"
      refute html =~ "set-event-key-42"
      refute html =~ "remove-set-song-42"
    end

    # O artista some da linha quando não há: o catálogo não o exige (US 2.1).
    test "o artista aparece só quando a música tem um" do
      assert linha(item(song: [artist: "Aline Barros"])) =~ "Aline Barros"
      refute linha(item()) =~ "<p class=\"text-muted-foreground text-sm\">"
    end
  end
end
