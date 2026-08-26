defmodule ChurchBandsWeb.EventSetComponents do
  @moduledoc """
  A linha do set de uma banda escalada, compartilhada pelas duas telas que a
  mostram (US 3.7): `EventSetLive.Show`, onde ela se edita, e `EventLive.Show`,
  onde ela só se lê.

  **Existe por causa do tom.** "Qual tom está valendo" é exatamente o tipo de
  regra que se duplica e depois diverge: são quatro estados, três deles
  parecidos o bastante para uma segunda escrita acertar por engano. Com um
  componente só, o que a tela do evento mostra e o que a tela do set mostra não
  têm como discordar.

  **`editable` é a diferença entre as duas**, e ela não é cosmética: sem ele a
  linha não tem alça de arraste, nem seletor de tom, nem botão de remover. A
  ordem é informação, não controle — e uma alça que não funciona é pior do que
  alça nenhuma. Esconder o controle continua não sendo autorização: quem manda
  o evento pelo socket é recusado por `EventSetLive.Show`, que reconfere
  `Schedule.manage_set?/2` em cada escrita.
  """
  use ChurchBandsWeb, :html

  @doc """
  Uma música do set, na posição em que ela toca.

  Recebe o item já com `band_key` — o tom do repertório daquela banda, que
  `Schedule.list_set/1` e `list_sets_for_event/1` trazem no mesmo `left_join`.

  `key_options` e `band_name` só são lidos quando `editable`: são o seletor de
  tom e a confirmação de remover, que a tela do evento não desenha.
  """
  attr :item, :map, required: true
  attr :index, :integer, required: true
  attr :editable, :boolean, default: false
  attr :key_options, :list, default: []
  attr :band_name, :string, default: nil

  def set_row(assigns) do
    assigns = assign(assigns, :key_state, effective_key(assigns.item, assigns.item.band_key))

    ~H"""
    <li
      id={"set-song-#{@item.id}"}
      data-set-item={@item.id}
      draggable={@editable && "true"}
      class="flex items-start gap-3 p-3 data-[dragging]:opacity-50"
    >
      <span :if={@editable} class="text-muted-foreground cursor-grab pt-2" aria-hidden="true">
        <.icon name="hero-bars-3" class="size-4" />
      </span>

      <span
        id={"set-position-#{@item.id}"}
        class="text-muted-foreground w-6 pt-2 text-right text-sm tabular-nums"
      >
        {@index}
      </span>

      <div class="min-w-0 flex-1 pt-1">
        <div class="flex items-center gap-2">
          <p class="font-medium">{@item.song.title}</p>
          <.link
            :if={@item.song.reference_url}
            id={"set-reference-#{@item.id}"}
            href={@item.song.reference_url}
            target="_blank"
            rel="noopener"
            aria-label={"Referência de #{@item.song.title}"}
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-play-circle" class="size-4" />
          </.link>
          <.link
            :if={@item.song.chord_chart_url}
            id={"set-chord-chart-#{@item.id}"}
            href={@item.song.chord_chart_url}
            target="_blank"
            rel="noopener"
            aria-label={"Cifra de #{@item.song.title}"}
            class="text-muted-foreground hover:text-foreground"
          >
            <.icon name="hero-document-text" class="size-4" />
          </.link>
        </div>
        <p :if={@item.song.artist} class="text-muted-foreground text-sm">{@item.song.artist}</p>
      </div>

      <div class="w-44">
        <p id={"set-key-#{@item.id}"} class="font-medium">{playing_key(@key_state)}</p>

        <p id={"set-key-note-#{@item.id}"} class="text-muted-foreground mt-0.5 text-xs">
          {key_note(@key_state)}
        </p>

        <form :if={@editable} id={"set-key-form-#{@item.id}"} phx-change="update_key" class="mt-1">
          <input type="hidden" name="item_id" value={@item.id} />
          <.select
            id={"set-event-key-#{@item.id}"}
            name="key"
            value={to_string(@item.key)}
            prompt="Tom da banda"
            options={@key_options}
            class="h-8 text-xs"
            aria-label={"Tom de #{@item.song.title} neste evento"}
          />
        </form>
      </div>

      <.button
        :if={@editable}
        id={"remove-set-song-#{@item.id}"}
        variant="ghost"
        size="sm"
        phx-click="remove"
        phx-value-id={@item.id}
        data-confirm={"Tirar \"#{@item.song.title}\" do set?\n\nEla continua no repertório da #{@band_name}."}
      >
        Remover
      </.button>
    </li>
    """
  end

  @doc """
  Qual tom está valendo naquela linha, e de onde ele veio.

  São três respostas, e cada uma diz uma coisa diferente:

    * `:orphan` — não há tom nenhum. A música saiu do repertório da banda
      depois de entrar no set, e o item não tem tom próprio. A trava de
      `Schedule.future_set_titles/3` só segura evento futuro, então o set de um
      culto passado alcança este caso
    * `{:band, tom}` — o tom do repertório, que é o normal: `key` nulo quer
      dizer *a banda toca como sempre toca*
    * `{:event, tom, tom_da_banda}` — a exceção daquele culto, com o tom da
      banda junto para a linha poder sinalizá-lo. `tom_da_banda` vem `nil`
      quando a música também saiu do repertório

  **Os três são marcados**, e não um par `{tom, tom_a_sinalizar}`: sem a
  etiqueta, "o tom da banda, sem exceção" e "a exceção de um item órfão" viram
  a mesma coisa — os dois teriam `nil` no segundo elemento — e a nota da linha
  perderia a diferença entre <q>Tom da banda: C</q> e <q>Só deste evento ·
  fora do repertório da banda</q>.
  """
  def effective_key(%{key: nil}, nil), do: :orphan
  def effective_key(%{key: nil}, band_key), do: {:band, band_key}
  def effective_key(%{key: key}, band_key), do: {:event, key, band_key}

  # O travessão é o item órfão: não há tom a mostrar, e um espaço em branco
  # pareceria falha de carregamento.
  defp playing_key(:orphan), do: "—"
  defp playing_key({:band, key}), do: to_string(key)
  defp playing_key({:event, key, _band_key}), do: to_string(key)

  # A nota diz **de onde o tom veio**, que é a informação que o tom sozinho
  # esconde: sem ela, "C" numa banda que toca em D pareceria o tom da banda.
  defp key_note(:orphan), do: "Fora do repertório da banda"
  defp key_note({:band, band_key}), do: "Tom da banda: #{band_key}"
  defp key_note({:event, _key, nil}), do: "Só deste evento · fora do repertório da banda"
  defp key_note({:event, _key, band_key}), do: "Só deste evento · a banda toca em #{band_key}"
end
