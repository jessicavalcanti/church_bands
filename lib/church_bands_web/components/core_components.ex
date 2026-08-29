defmodule ChurchBandsWeb.CoreComponents do
  @moduledoc """
  Componentes do projeto que o SaladUI não cobre.

  Desde a US 1.9 a base visual é o [SaladUI](https://hexdocs.pm/salad_ui) —
  port do shadcn/ui para LiveView, com os componentes copiados para
  `lib/church_bands_web/components/ui/`. Botão, campo de texto, textarea,
  rótulo, tabela, cartão, selo e companhia vêm de lá, e este módulo ficou só
  com o que é do projeto:

    * `header/1` — o título e o subtítulo que abrem cada tela
    * `worship_illustration/1` — o desenho que abre as telas públicas
    * `icon/1` — heroicons, a mesma regra de sempre
    * `user_photo/1` — a foto de perfil, ou o lugar dela em quem não tem
    * `select/1` — um `<select>` nativo. O `select` do SaladUI é uma lista
      construída em JavaScript, que não é um campo de formulário de verdade:
      não submete sozinho, e não dá para dirigir por teste
    * `table/1` — a tabela com slots `:col`/`:action` e suporte a stream,
      montada sobre as peças de tabela do SaladUI

  Referências úteis:

    * [SaladUI](https://hexdocs.pm/salad_ui) — os componentes copiados
    * [Tailwind CSS](https://tailwindcss.com) — layout, tamanho, espaçamento
    * [Heroicons](https://heroicons.com) — ver `icon/1`
    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html)
  """
  use Phoenix.Component
  use Gettext, backend: ChurchBandsWeb.Gettext

  alias ChurchBandsWeb.Components.UI
  alias Phoenix.LiveView.JS

  @doc """
  Renderiza o cabeçalho de uma tela: título e subtítulo.

  ## Exemplos

      <.header>
        Bandas
        <:subtitle>As bandas do grupo de louvor.</:subtitle>
      </.header>

  As ações da tela não moram aqui: elas ficam no slot `:actions` de
  `ChurchBandsWeb.Layouts.app/1`, na faixa superior do portal.
  """
  attr :class, :any, default: nil

  slot :inner_block, required: true
  slot :subtitle

  def header(assigns) do
    ~H"""
    <header class={["pb-4", @class]}>
      <h1 class="text-lg font-semibold leading-8 tracking-tight">
        {render_slot(@inner_block)}
      </h1>
      <p :if={@subtitle != []} class="text-sm text-muted-foreground">
        {render_slot(@subtitle)}
      </p>
    </header>
    """
  end

  @doc """
  A ilustração das telas públicas: a fachada da igreja e a música que sai dela.

  Um arco ogival com a cruz no alto e a rosácea, o microfone no meio da nave e
  as notas subindo dos dois lados — igreja e banda de louvor na mesma imagem,
  que é o que a vitrine de `/` e o `/login` dizem antes de qualquer texto.

  **É desenho no código, e não um arquivo em `priv/static`, por causa do modo
  escuro.** Ele é a classe `.dark` no `<html>`, escolhida à mão e guardada no
  `localStorage` — não `prefers-color-scheme`. Um `<img>` não enxerga a classe
  do documento que o contém, então a mesma imagem serviria as duas telas com o
  traço preto, e no tema escuro ela sumiria no fundo. Em SVG inline o traço é
  `currentColor`, e a opacidade é o que separa os planos: primeiro o arco,
  depois as notas, por último a fachada em volta.

  Não tem `attr` nenhum de propósito: as duas telas mostram a mesma peça, do
  mesmo tamanho, no mesmo lugar. `aria-hidden` porque ela é decoração — o que
  a tela informa está no `header/1` logo abaixo.

  ## Exemplos

      <.worship_illustration />
  """
  def worship_illustration(assigns) do
    ~H"""
    <svg
      id="worship-illustration"
      viewBox="0 0 320 192"
      aria-hidden="true"
      class="text-foreground mx-auto w-full max-w-72"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <%!-- O chão, que é o que apoia as três janelas na mesma linha. --%>
      <path d="M18 180H302" opacity=".25" />

      <%!-- A fachada em volta: as janelas laterais ficam no plano de trás. --%>
      <path d="M52 180v-30a20 20 0 0 1 40 0v30" opacity=".4" />
      <path d="M72 130v50" opacity=".25" />
      <path d="M228 180v-30a20 20 0 0 1 40 0v30" opacity=".4" />
      <path d="M248 130v50" opacity=".25" />

      <%!-- O arco ogival e a cruz sobre ele. --%>
      <path d="M115 180v-70a90 90 0 0 1 45-77.9 90 90 0 0 1 45 77.9v70" />
      <path d="M160 30V8" />
      <path d="M151 17h18" />

      <%!-- A rosácea. --%>
      <circle cx="160" cy="70" r="12" opacity=".4" />
      <path d="M160 58v24M148 70h24M151.5 61.5l17 17M168.5 61.5l-17 17" opacity=".4" />

      <%!-- O microfone de pedestal, no meio da nave. --%>
      <rect x="152" y="96" width="16" height="30" rx="8" />
      <path d="M152.5 106h15M152.5 114h15" opacity=".45" />
      <path d="M144 118a16 16 0 0 0 32 0" />
      <path d="M160 134v42" />
      <path d="M147 176h26" />

      <%!-- As notas: uma colcheia dupla à esquerda, uma solta à direita. --%>
      <g fill="currentColor" stroke="none" opacity=".7">
        <ellipse cx="44" cy="88" rx="7" ry="5.2" transform="rotate(-20 44 88)" />
        <ellipse cx="72" cy="80" rx="7" ry="5.2" transform="rotate(-20 72 80)" />
        <ellipse cx="250" cy="86" rx="7" ry="5.2" transform="rotate(-20 250 86)" />
      </g>
      <g opacity=".7">
        <path d="M50.5 85.5V52" />
        <path d="M78.5 77.5V44" />
        <path d="M50 52.5 78.5 44.5" stroke-width="3.2" />
        <path d="M256.5 83.5V50" />
        <path d="M256.5 50c10 4 12 12 6 20" />
      </g>
    </svg>
    """
  end

  @doc """
  A foto de perfil de `user` — ou, quando não há foto, o lugar dela.

  `referrerpolicy="no-referrer"` mora aqui e num lugar só: a foto é um endereço
  que cada pessoa escolhe, em qualquer host, e sem ele abrir a lista de pessoas
  contaria a todos esses hosts qual página estava sendo vista.

  ## Exemplos

      <.user_photo id="profile-photo" user={@current_user} />
      <.user_photo id={"user-photo-\#{user.id}"} user={user} size={:sm} />
  """
  attr :id, :string, required: true, doc: "o id da foto; o lugar dela vira `<id>-placeholder`"
  attr :user, :map, required: true, doc: "quem é dono da foto — precisa de `photo_url` e `name`"

  attr :size, :atom,
    default: :lg,
    values: [:sm, :lg],
    doc: "`:lg` abre uma tela, `:sm` acompanha uma linha de lista"

  def user_photo(assigns) do
    # As classes de tamanho ficam escritas por extenso, e não montadas com
    # interpolação: o Tailwind lê o código-fonte para saber quais classes gerar,
    # e uma classe montada em tempo de execução ele não enxerga.
    assigns = assign(assigns, :sizes, photo_sizes(assigns.size))

    ~H"""
    <img
      :if={@user.photo_url}
      id={@id}
      src={@user.photo_url}
      alt={"Foto de #{@user.name}"}
      referrerpolicy="no-referrer"
      class={["ring-border rounded-full object-cover", @sizes.frame, @sizes.ring]}
    />
    <div
      :if={is_nil(@user.photo_url)}
      id={"#{@id}-placeholder"}
      class={[
        "bg-muted text-muted-foreground flex items-center justify-center rounded-full",
        @sizes.frame
      ]}
    >
      <.icon name="hero-user" class={@sizes.icon} />
    </div>
    """
  end

  defp photo_sizes(:lg), do: %{frame: "size-16", ring: "ring-2", icon: "size-8"}
  defp photo_sizes(:sm), do: %{frame: "size-10", ring: "ring-1", icon: "size-5"}

  @doc """
  Renderiza um `<select>` nativo, com o mesmo visual dos campos do SaladUI.

  O `select` do SaladUI é uma lista construída em JavaScript: bonita, mas não é
  um `<select>` — não submete sem o hook, e não há como um teste escolher uma
  opção nela. Como as escolhas deste sistema (líder de banda, papel de acesso,
  naipe) são todas de uma lista curta e precisam funcionar sem JavaScript, o
  campo nativo continua sendo o certo aqui.

  ## Exemplos

      <.select field={@form[:leader_id]} prompt="Escolha o líder" options={@leader_options} />
  """
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any, default: nil

  attr :field, Phoenix.HTML.FormField,
    default: nil,
    doc: "o campo do formulário, por exemplo @form[:leader_id]"

  attr :prompt, :string, default: nil, doc: "a opção vazia que abre a lista"
  attr :options, :list, default: [], doc: "as opções, para Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form required size)

  def select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(:field, nil)
    |> assign(:errors, UI.Helpers.field_errors(field))
    |> assign(:id, assigns.id || field.id)
    |> assign(
      :name,
      assigns.name || if(assigns.multiple, do: field.name <> "[]", else: field.name)
    )
    |> assign(:value, if(is_nil(assigns.value), do: field.value, else: assigns.value))
    |> select()
  end

  def select(assigns) do
    assigns = assign_new(assigns, :errors, fn -> [] end)

    ~H"""
    <select
      id={@id}
      name={@name}
      multiple={@multiple}
      class={[
        "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm",
        "focus-visible:outline-hidden focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]",
        "disabled:cursor-not-allowed disabled:opacity-50",
        @errors != [] && "border-destructive",
        @class
      ]}
      {@rest}
    >
      <option :if={@prompt} value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
    </select>
    """
  end

  @doc """
  Renderiza uma tabela com slots `:col` e `:action`.

  As peças visuais são as do SaladUI (`table`, `table_header`, `table_row`…);
  o que é do projeto é a montagem por slots e o suporte a `stream`, de que as
  quatro listagens do sistema dependem — e o `id` no `<tbody>`, que é contrato
  dos testes.

  ## Exemplos

      <.table id="users" rows={@streams.users}>
        <:col :let={{_id, user}} label="Nome">{user.name}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "a função que gera o id de cada linha"
  attr :row_click, :any, default: nil, doc: "a função de phx-click de cada linha"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "a função que mapeia cada linha antes dos slots :col e :action"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "as ações de cada linha, na última coluna"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="w-full overflow-x-auto">
      <UI.Table.table>
        <UI.Table.table_header>
          <UI.Table.table_row>
            <UI.Table.table_head :for={col <- @col}>{col[:label]}</UI.Table.table_head>
            <UI.Table.table_head :if={@action != []}>
              <span class="sr-only">Ações</span>
            </UI.Table.table_head>
          </UI.Table.table_row>
        </UI.Table.table_header>
        <UI.Table.table_body
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
        >
          <UI.Table.table_row :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <UI.Table.table_cell
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["align-top", @row_click && "hover:cursor-pointer"]}
            >
              {render_slot(col, @row_item.(row))}
            </UI.Table.table_cell>
            <UI.Table.table_cell :if={@action != []} class="w-0 align-top">
              <div class="flex gap-2">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </UI.Table.table_cell>
          </UI.Table.table_row>
        </UI.Table.table_body>
      </UI.Table.table>
    </div>
    """
  end

  @doc """
  Renderiza um [Heroicon](https://heroicons.com).

  Heroicons vêm em três estilos — outline, solid e mini. O padrão é outline;
  solid e mini saem dos sufixos `-solid` e `-mini`.

  Os ícones são extraídos de `deps/heroicons` e entram no `app.css` compilado
  pelo plugin em `assets/vendor/heroicons.js`.

  ## Exemplos

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## Comandos JS

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Traduz uma mensagem de erro pelo gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ChurchBandsWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ChurchBandsWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Traduz os erros de um campo a partir de uma lista de erros.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
