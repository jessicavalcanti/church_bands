defmodule ChurchBandsWeb.Layouts do
  @moduledoc """
  As duas molduras do sistema (US 1.9).

    * `app/1` — o portal de quem está logado: barra lateral fixa à esquerda,
      faixa superior com o gatilho do menu e o breadcrumb, conteúdo abaixo
    * `public/1` — login, ativação de conta, recuperação de senha e a vitrine
      de `/` para visitante. Sem barra lateral e sem breadcrumb: antes de
      entrar não há para onde navegar

  Esconder um item do menu **não** é autorização: quem decide é o hook da
  `live_session` no router. O menu mostra o que a pessoa pode acessar porque
  oferecer um caminho que termina em recusa é um mau portal, não porque a
  barra lateral protege alguma coisa.
  """
  use ChurchBandsWeb, :html

  import ChurchBandsWeb.Components.UI.Avatar
  import ChurchBandsWeb.Components.UI.Breadcrumb
  import ChurchBandsWeb.Components.UI.DropdownMenu
  import ChurchBandsWeb.Components.UI.Separator
  import ChurchBandsWeb.Components.UI.Sidebar

  alias ChurchBands.Accounts.User

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @desktop_sidebar_id "app-sidebar"
  @mobile_sidebar_id "app-sidebar-mobile"

  @doc """
  O portal: barra lateral, faixa do breadcrumb e o conteúdo da tela.

  ## Exemplos

      <Layouts.app
        flash={@flash}
        current_user={@current_user}
        current_path={@current_path}
        csp_nonce={@csp_nonce}
        breadcrumb={[{"Bandas", ~p"/bands"}, {@band.name, nil}]}
      >
        <.header>Banda Jovem</.header>
      </Layouts.app>
  """
  attr :flash, :map, required: true

  attr :current_user, :map,
    default: nil,
    doc: "o usuário logado — o portal só existe para quem está logado"

  attr :current_path, :string,
    default: "/",
    doc: "o caminho da tela aberta, para destacar o item do menu"

  attr :csp_nonce, :string,
    required: true,
    doc: """
    o nonce da CSP daquela resposta, que assina o script inline da barra
    lateral. Obrigatório de propósito: sem ele o navegador bloqueia o script e
    a barra recolhida volta a piscar (#31), e uma tela nova que esquecesse de
    passá-lo não daria nenhum sinal em tempo de execução — assim o
    `--warnings-as-errors` do `precommit` avisa antes
    """

  attr :breadcrumb, :list,
    default: [],
    doc: """
    o caminho da tela na estrutura, como uma lista de `{rótulo, caminho}` a
    partir de *Início* — o último item sem caminho. Montado por assign, e não
    lido da URL, porque é assim que `:id` vira o nome da banda ou da pessoa
    """

  slot :actions, doc: "os botões de ação da tela, na faixa superior"
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:desktop_sidebar_id, @desktop_sidebar_id)
      |> assign(:mobile_sidebar_id, @mobile_sidebar_id)
      |> assign(:trail, trail(assigns.breadcrumb))

    ~H"""
    <.sidebar_provider>
      <.sidebar id={@desktop_sidebar_id} collapsible="icon">
        <.sidebar_body current_user={@current_user} current_path={@current_path} />
      </.sidebar>
      <%!-- A barra recolhida precisa já **nascer** recolhida.

      O servidor sempre manda a barra expandida (o `state` do `<.sidebar>` é do
      componente, não de quem está usando), e quem devolve a escolha é o hook
      `SidebarState` — que só roda depois de o `app.js` carregar e a LiveView
      montar. Numa troca de tela que recarrega a página inteira (a home `/` é
      controller, `/admin/invites` é outra `live_session`) isso são vários
      quadros com a barra aberta antes de ela fechar, e fechar animando os
      200ms da transição de largura: é a piscada que se vê.

      Por isso este script inline, no mesmo espírito do script de tema do
      `root.html.heex`: ele bloqueia o parser aqui, logo abaixo da barra, e
      corrige os atributos antes da primeira pintura. Fica no corpo, e não no
      `<head>`, porque lá a barra ainda não existe.

      A LiveView não reexecuta `<script>` que chega por diff, então ele roda
      uma vez por carregamento de página — e a navegação ao vivo, que não
      recarrega nada, continua por conta do hook.

      Sem `phx-no-format`, de propósito: com ele o formatador do HEEx acrescenta
      dois espaços ao corpo do script **a cada passada**, e o `git diff
      --exit-code` do CI nunca fecha. Deixando o formatador mandar, a indentação
      tem ponto fixo. --%>
      <script
        nonce={@csp_nonce}
        data-sidebar-target={@desktop_sidebar_id}
        data-sidebar-collapsible="icon"
      >
        (() => {
          // A mesma chave do `assets/js/hooks/sidebar_state.js`. Não dá para
          // importar de lá: aqui é antes de qualquer bundle existir.
          const script = document.currentScript;
          let state = null;
          try { state = localStorage.getItem("phx:sidebar") } catch (_error) {}
          if (state !== "collapsed") return;

          const sidebar = document.getElementById(script.dataset.sidebarTarget);
          if (!sidebar) return;

          sidebar.setAttribute("data-state", "collapsed");
          sidebar.setAttribute("data-collapsible", script.dataset.sidebarCollapsible);
        })();
      </script>

      <%!-- Recolher a barra acontece só no navegador: o gatilho do SaladUI vira
      atributos no DOM e o servidor nunca sabe. Este ponto de apoio existe para
      pendurar o hook que guarda e devolve a escolha — ele não desenha nada, e
      mora fora da barra porque `<.sidebar>` monta os próprios atributos. --%>
      <div
        id="sidebar-state"
        class="hidden"
        phx-hook="SidebarState"
        data-sidebar-target={@desktop_sidebar_id}
        data-sidebar-collapsible="icon"
      />

      <div class="md:hidden">
        <.sidebar id={@mobile_sidebar_id} is_mobile>
          <.sidebar_body
            current_user={@current_user}
            current_path={@current_path}
            id_suffix="-mobile"
          />
        </.sidebar>
      </div>

      <.sidebar_inset>
        <header class="bg-background/95 supports-backdrop-filter:bg-background/60 sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b px-4 backdrop-blur">
          <.sidebar_trigger target={@desktop_sidebar_id} class="hidden md:inline-flex" />

          <button
            type="button"
            id="mobile-sidebar-trigger"
            aria-label="Abrir menu"
            class={[button_variant(%{variant: "ghost", size: "icon"}), "h-7 w-7 md:hidden"]}
            phx-click={
              JS.dispatch("salad_ui:command",
                to: "#" <> @mobile_sidebar_id,
                detail: %{command: "open"}
              )
            }
          >
            <.icon name="hero-bars-3" class="size-4" />
          </button>

          <.separator orientation="vertical" class="mr-1 h-4" />

          <.breadcrumb id="breadcrumb">
            <.breadcrumb_list>
              <%= for {{label, path}, index} <- Enum.with_index(@trail) do %>
                <.breadcrumb_separator :if={index > 0} />
                <.breadcrumb_item class={index > 0 && index < length(@trail) - 1 && "hidden md:flex"}>
                  <.breadcrumb_link :if={path} navigate={path}>{label}</.breadcrumb_link>
                  <.breadcrumb_page :if={is_nil(path)}>{label}</.breadcrumb_page>
                </.breadcrumb_item>
              <% end %>
            </.breadcrumb_list>
          </.breadcrumb>

          <div :if={@actions != []} class="ml-auto flex items-center gap-2">
            {render_slot(@actions)}
          </div>
        </header>

        <div class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-4xl space-y-4">
            {render_slot(@inner_block)}
          </div>
        </div>
      </.sidebar_inset>
    </.sidebar_provider>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  A moldura das telas públicas: login, ativação de conta, recuperação de senha
  e a vitrine de `/` para quem não entrou.

  Sem barra lateral e sem breadcrumb — não há para onde navegar antes de
  entrar. Só a marca no topo e o conteúdo centrado.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def public(assigns) do
    ~H"""
    <div class="flex min-h-svh flex-col">
      <header class="flex h-14 shrink-0 items-center border-b px-4 sm:px-6 lg:px-8">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2 font-semibold tracking-tight">
          <.icon name="hero-musical-note" class="size-5" /> Grupo de Louvor
        </.link>
      </header>

      <main class="flex flex-1 items-start justify-center px-4 py-16 sm:px-6 lg:px-8">
        <div class="w-full max-w-sm space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # A barra lateral em si. Sai daqui duas vezes — a fixa do desktop e a gaveta
  # do celular — por isso os ids recebem sufixo: o contrato de teste é o par
  # sem sufixo, o do desktop.
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: "/"
  attr :id_suffix, :string, default: ""

  defp sidebar_body(assigns) do
    assigns = assign(assigns, :items, menu_items(assigns.current_user))

    ~H"""
    <.sidebar_header>
      <.link
        navigate={~p"/"}
        class="flex items-center gap-2 px-2 py-1 font-semibold tracking-tight"
      >
        <.icon name="hero-musical-note" class="size-5 shrink-0" />
        <span class="truncate group-data-[collapsible=icon]:hidden">Grupo de Louvor</span>
      </.link>
    </.sidebar_header>

    <.sidebar_content>
      <.sidebar_group>
        <.sidebar_group_content>
          <.sidebar_menu>
            <.sidebar_menu_item :for={item <- @items}>
              <.sidebar_menu_button
                id={item.id <> @id_suffix}
                navigate={item.path}
                is_active={active?(@current_path, item.path)}
                tooltip={item.label}
              >
                <.icon name={item.icon} class="size-4 shrink-0" />
                <span>{item.label}</span>
              </.sidebar_menu_button>
            </.sidebar_menu_item>
          </.sidebar_menu>
        </.sidebar_group_content>
      </.sidebar_group>
    </.sidebar_content>

    <.sidebar_footer :if={@current_user}>
      <.sidebar_menu>
        <.sidebar_menu_item>
          <.dropdown_menu id={"user-menu" <> @id_suffix} class="block w-full">
            <.dropdown_menu_trigger class="w-full">
              <span class={[
                "flex w-full items-center gap-2 overflow-hidden rounded-md p-2 text-left text-sm",
                "hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                "group-data-[collapsible=icon]:!size-8 group-data-[collapsible=icon]:!p-2"
              ]}>
                <.avatar class="size-6 shrink-0 rounded-md">
                  <.avatar_image
                    :if={@current_user.photo_url}
                    id={"sidebar-avatar" <> @id_suffix}
                    src={@current_user.photo_url}
                    alt={"Foto de #{@current_user.name}"}
                    referrerpolicy="no-referrer"
                  />
                  <.avatar_fallback class="rounded-md text-[10px]">
                    {initials(@current_user.name)}
                  </.avatar_fallback>
                </.avatar>
                <span class="grid flex-1 text-left leading-tight group-data-[collapsible=icon]:hidden">
                  <span class="truncate font-medium">{@current_user.name}</span>
                  <span class="text-muted-foreground truncate text-xs">
                    {User.role_label(@current_user.global_role)}
                  </span>
                </span>
              </span>
            </.dropdown_menu_trigger>

            <.dropdown_menu_content side="top" align="start" class="w-56">
              <.dropdown_menu_label class="truncate font-normal">
                {@current_user.email}
              </.dropdown_menu_label>
              <.dropdown_menu_separator />
              <.dropdown_menu_link_item
                id={"profile-link" <> @id_suffix}
                navigate={~p"/profile"}
                class="gap-2"
              >
                <.icon name="hero-user-circle" class="size-4" /> Meu perfil
              </.dropdown_menu_link_item>
              <.dropdown_menu_separator />
              <div class="px-2 py-1.5">
                <p class="text-muted-foreground mb-1.5 text-xs">Tema</p>
                <.theme_toggle />
              </div>
              <.dropdown_menu_separator />
              <.dropdown_menu_link_item
                id={"logout-link" <> @id_suffix}
                href={~p"/logout"}
                method="delete"
                class="gap-2"
              >
                <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Sair
              </.dropdown_menu_link_item>
            </.dropdown_menu_content>
          </.dropdown_menu>
        </.sidebar_menu_item>
      </.sidebar_menu>
    </.sidebar_footer>
    """
  end

  # Os itens do menu, na ordem em que aparecem. `full_access?: true` marca os
  # que só Pastor e Líder de Louvor veem — `Instrumentos` (US 2.8) e
  # `Convites`. A proteção de verdade está no router; aqui é só não oferecer um
  # caminho que terminaria em recusa.
  #
  # `Músicas` saiu dessa marca na US 2.5: o catálogo abriu para leitura ampla,
  # e esconder o item de quem pode entrar seria esconder a tela de quem ela
  # passou a servir.
  @menu_items [
    %{id: "home-link", label: "Início", path: "/", icon: "hero-home", full_access?: false},
    %{
      id: "bands-link",
      label: "Bandas",
      path: "/bands",
      icon: "hero-musical-note",
      full_access?: false
    },
    %{
      id: "songs-link",
      label: "Músicas",
      path: "/songs",
      icon: "hero-queue-list",
      full_access?: false
    },
    %{
      id: "users-link",
      label: "Pessoas",
      path: "/users",
      icon: "hero-users",
      full_access?: false
    },
    %{
      id: "instruments-link",
      label: "Instrumentos",
      path: "/instruments",
      icon: "hero-radio",
      full_access?: true
    },
    %{
      id: "invites-link",
      label: "Convites",
      path: "/admin/invites",
      icon: "hero-envelope",
      full_access?: true
    }
  ]

  defp menu_items(nil), do: []

  defp menu_items(user) do
    full_access? = ChurchBands.Accounts.full_access?(user)

    Enum.filter(@menu_items, &(full_access? or not &1.full_access?))
  end

  defp active?(current_path, "/"), do: current_path == "/"
  defp active?(current_path, path), do: String.starts_with?(current_path || "", path)

  # A raiz da trilha é sempre *Início*: em `/` como texto, nas outras telas
  # como link.
  defp trail([]), do: [{"Início", nil}]
  defp trail(items), do: [{"Início", "/"} | items]

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.upcase(String.first(&1) || ""))
  end

  @doc """
  As mensagens de flash, empilhadas no canto superior direito.

  ## Exemplos

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed top-4 right-4 z-50 flex w-80 flex-col gap-2 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Uma mensagem de flash, sobre o `alert` do SaladUI.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role="alert"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      class="pointer-events-auto cursor-pointer"
      {@rest}
    >
      <.alert
        variant={(@kind == :error && "destructive") || "default"}
        class="bg-background shadow-lg"
      >
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-4" />
        <.alert_title :if={@title}>{@title}</.alert_title>
        <.alert_description>{msg}</.alert_description>
      </.alert>
    </div>
    """
  end

  @doc """
  O seletor de tema: sistema, claro e escuro.

  O `<html>` carrega a classe `.dark` (que é como o SaladUI liga o `dark:` do
  Tailwind) e mais dois atributos: `data-theme` com o tema em vigor e
  `data-theme-source` com a origem da escolha. O botão em destaque abaixo lê
  esses dois. Ver o `<head>` do `root.html.heex`, que aplica o tema antes de a
  página pintar.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="border-input bg-muted grid grid-cols-3 gap-1 rounded-md border p-1">
      <button
        :for={
          {theme, icon, label} <- [
            {"system", "hero-computer-desktop-micro", "Sistema"},
            {"light", "hero-sun-micro", "Claro"},
            {"dark", "hero-moon-micro", "Escuro"}
          ]
        }
        type="button"
        title={label}
        aria-label={label}
        class={[
          "flex cursor-pointer items-center justify-center rounded-sm px-2 py-1 transition-colors",
          "hover:bg-background/60",
          theme_button_state(theme)
        ]}
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme={theme}
      >
        <.icon name={icon} class="size-4" />
      </button>
    </div>
    """
  end

  # O tema escolhido fica em destaque. `system` é reconhecido pela origem, não
  # pelo tema em vigor — quem escolheu "sistema" e está no escuro não deve ver
  # "escuro" marcado.
  defp theme_button_state("system"),
    do: "[[data-theme-source=system]_&]:bg-background [[data-theme-source=system]_&]:shadow-sm"

  defp theme_button_state(theme) do
    [
      "[[data-theme-source=user][data-theme=#{theme}]_&]:bg-background",
      "[[data-theme-source=user][data-theme=#{theme}]_&]:shadow-sm"
    ]
  end
end
