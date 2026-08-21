// Guarda entre carregamentos se a barra lateral está recolhida.
//
// Recolher a barra é 100% client-side: o `sidebar_trigger` do SaladUI dispara
// `JS.toggle_attribute`, que só vira atributos no DOM — o servidor nunca fica
// sabendo. Este hook observa esses atributos, grava a escolha no
// `localStorage` e a aplica de volta a cada montagem, no mesmo espírito do
// script de tema do `root.html.heex`.
//
// O hook não mora na própria barra: `<.sidebar>` monta os atributos dela e não
// repassa os nossos. Ele fica num ponto de apoio invisível que aponta para a
// barra por `data-sidebar-target`.
const KEY = "phx:sidebar"

const read = () => {
  try {
    return localStorage.getItem(KEY)
  } catch (_error) {
    // Navegador com armazenamento bloqueado: a barra abre expandida e segue.
    return null
  }
}

const write = (state) => {
  try {
    localStorage.setItem(KEY, state)
  } catch (_error) {
    // Sem onde guardar, a escolha vale só para esta visita.
  }
}

export const SidebarState = {
  mounted() {
    this.sidebar = document.getElementById(this.el.dataset.sidebarTarget)
    if (!this.sidebar) return

    this.restore()
    this.observer = new MutationObserver(() => write(this.sidebar.dataset.state || "expanded"))
    this.observer.observe(this.sidebar, {attributes: true, attributeFilter: ["data-state"]})
  },

  destroyed() {
    this.observer && this.observer.disconnect()
  },

  // Os dois atributos andam juntos: é o par que o `toggle_sidebar/1` do
  // SaladUI alterna, e é de `data-collapsible` que saem as classes do modo só
  // com ícones.
  restore() {
    if (read() !== "collapsed") return

    this.sidebar.setAttribute("data-state", "collapsed")
    this.sidebar.setAttribute("data-collapsible", this.el.dataset.sidebarCollapsible || "icon")
  }
}
