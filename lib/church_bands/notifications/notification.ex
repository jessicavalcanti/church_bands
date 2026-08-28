defmodule ChurchBands.Notifications.Notification do
  @moduledoc """
  Uma notificação dentro da plataforma (US 4.5).

  **Ela é de uma pessoa, e existe para ser lida por ela.** Não há notificação
  de banda nem de papel: o que a torna sua é a chave, e é ela que faz o
  `on_delete: :delete_all` levar o histórico junto quando a conta some.

  **A linha não sabe de que assunto ela nasceu.** Não há `swap_request_id`
  aqui, e a ausência é o desenho: a troca é o primeiro emissor, não o único
  previsto, e uma coluna por origem obrigaria uma migration a cada assunto novo
  que quisesse avisar alguém. O que se grava é *para quem, de que tipo, título,
  texto e para onde leva*.

  **`title`, `body` e `path` são escritos no momento do fato e nunca se
  recalculam.** A notificação conta o que aconteceu **naquele dia**: se o culto
  mudar de nome depois, a mensagem continua sendo a que foi dita. É a diferença
  entre um aviso e uma consulta — montá-la na leitura reescreveria o passado.

  **`read_at` fica fora do `cast/3`.** Marcar como lida é operação própria do
  contexto, e não campo de formulário — o mesmo arranjo do `status` do `Event`
  (US 3.2) e do `status` do `SwapRequest` (US 4.2).

  **Os quatro tipos nascem todos da troca**, e é por isso que são só quatro:
  valor de enum que nenhum caminho alcança é ramo morto, e cada assunto novo
  entra na história que sabe produzi-lo.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Accounts.User

  @kinds [:swap_requested, :swap_cancelled, :swap_accepted, :swap_declined]

  schema "notifications" do
    field :kind, Ecto.Enum, values: @kinds
    field :title, :string
    field :body, :string
    field :path, :string
    field :read_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset da notificação.

  Tudo é obrigatório menos `read_at`, que nem chega a ser aceito: a notificação
  **nasce não lida**, sempre, e quem a marca depois é `Notifications.mark_read/2`.
  """
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :kind, :title, :body, :path])
    |> validate_required([:user_id, :kind, :title, :body, :path])
    |> assoc_constraint(:user)
  end
end
