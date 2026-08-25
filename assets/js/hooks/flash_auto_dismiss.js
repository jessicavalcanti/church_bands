// O aviso do canto some sozinho depois de `data-duration` milissegundos (#87).
//
// O relógio **executa o `phx-click` do próprio elemento** em vez de esconder o
// aviso por conta própria. São dois motivos:
//
//   * o flash mora no socket, não no DOM. Esconder sem disparar
//     `lv:clear-flash` deixaria a mensagem no servidor, e o próximo re-render
//     traria o aviso de volta — sumiria e voltaria, que é pior que ficar;
//   * o clique já faz as duas coisas, na ordem certa e com a transição de
//     saída. Sumir sozinho e fechar no `x` passam a ser o mesmo caminho, e não
//     dois que precisam ser mantidos iguais.
export const FlashAutoDismiss = {
  mounted() {
    this.message = this.el.textContent
    this.arm()

    // Com o ponteiro em cima o relógio para, como no Sonner (de quem o toast
    // do SaladUI é porte): senão o aviso some no meio do caminho do mouse até
    // o `x`, e quem estava lendo perde a mensagem.
    this.el.addEventListener("mouseenter", () => this.disarm())
    this.el.addEventListener("mouseleave", () => this.arm())
  },

  updated() {
    // Um aviso novo do mesmo tipo reaproveita o elemento: só o texto muda.
    // Reiniciar a contagem a cada atualização deixaria o aviso preso na tela
    // enquanto a tela renderizasse por outro motivo — que é o defeito que este
    // hook conserta.
    if (this.el.textContent === this.message) return

    this.message = this.el.textContent
    this.arm()
  },

  destroyed() {
    this.disarm()
  },

  arm() {
    this.disarm()

    this.timer = setTimeout(
      () => this.js().exec(this.el.getAttribute("phx-click")),
      Number(this.el.dataset.duration),
    )
  },

  disarm() {
    clearTimeout(this.timer)
  },
}
