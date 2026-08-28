defmodule ChurchBandsWeb.NotificationController do
  @moduledoc """
  Abrir uma notificação a partir da home (US 4.6).

  **Existe porque a home é tela de controller.** Na central (US 4.5) abrir uma
  notificação é um `phx-click` — a tela é uma LiveView, e o socket leva o
  clique. A home não tem socket, e o resumo dela precisa fazer exatamente a
  mesma coisa: marcar como lida e seguir para o caminho da notificação
  (regra 7). Este controller é essa porta.

  **É `POST`, e não um link comum**, pelo mesmo motivo que a central usa um
  botão: abrir **escreve**. Um `GET` que marca como lida seria marcado por
  qualquer coisa que resolva o endereço antes da pessoa clicar. O link da home
  sai com `method="post"`, e o token de CSRF vai junto — é o mesmo arranjo do
  *Sair* da moldura.

  **A recusa é a mesma da central**, e por isso não distingue o id de outra
  pessoa do id inventado: `Notifications.get_for_user/2` já filtra pelo dono
  dentro da consulta, e dizer <q>existe, mas não é sua</q> contaria alguma
  coisa sobre a vida de terceiros. Quem cai nela volta para a home com
  <q>Notificação não encontrada.</q>
  """
  use ChurchBandsWeb, :controller

  alias ChurchBands.Notifications

  def open(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Notifications.get_for_user(user, id) do
      nil ->
        conn
        |> put_flash(:error, "Notificação não encontrada.")
        |> redirect(to: ~p"/")

      notification ->
        Notifications.mark_read(user, notification)
        redirect(conn, to: notification.path)
    end
  end
end
