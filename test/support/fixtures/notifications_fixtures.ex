defmodule ChurchBands.NotificationsFixtures do
  @moduledoc """
  Fixtures para o contexto `ChurchBands.Notifications`.
  """

  alias ChurchBands.LocalTime
  alias ChurchBands.Notifications.Notification
  alias ChurchBands.Repo

  @doc """
  Grava uma notificação para `user`.

  Vai **direto ao repositório**, e não por `Notifications.notify/3`, por dois
  motivos: `read_at` fica fora do `changeset/2` de propósito — marcar como lida
  é operação do contexto —, e é justamente <q>esta já estava lida</q> que
  metade dos testes precisa montar. Aceita também `:inserted_at`, que é como se
  monta a ordem da lista sem depender do relógio.

  Os padrões descrevem uma notificação de troca de verdade, que é a única
  origem que existe hoje.
  """
  def notification_fixture(user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    %Notification{}
    |> Ecto.Changeset.change(
      user_id: user.id,
      kind: Map.get(attrs, :kind, :swap_requested),
      title: Map.get(attrs, :title, "Pedido de troca de escala"),
      body: Map.get(attrs, :body, "Alguém pediu troca com você."),
      path: Map.get(attrs, :path, "/swaps?from=notification"),
      read_at: Map.get(attrs, :read_at),
      inserted_at: Map.get(attrs, :inserted_at, LocalTime.now())
    )
    |> Repo.insert!()
  end
end
