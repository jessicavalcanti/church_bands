defmodule ChurchBands.Swaps.SwapRequest do
  @moduledoc """
  Um pedido de troca de escala (US 4.2).

  **O pedido é de vaga para vaga, não de pessoa para pessoa.** A linha guarda as
  duas escalas (`event_bands`) e os dois vínculos (`band_members`) — nunca
  `user_id`. Quem é a pessoa se lê do vínculo; qual o evento, da escala. É o que
  faz o pedido morrer sozinho quando a banda sai da escala ou a pessoa sai da
  banda, pelo `on_delete: :delete_all` das quatro chaves, sem nenhuma limpeza
  escrita à mão.

  **`status` fica fora do `cast/3`.** Quem o muda é o contexto, por `change/2` —
  o mesmo cuidado do `status` do `Event` (US 3.2): um parâmetro forjado no
  formulário não cancela pedido pela porta dos fundos.

  **`:accepted` e `:declined` não existem aqui**, e é de propósito: a cobertura
  é 100% e valor de enum que nenhum caminho alcança é ramo morto. Cada estado
  entra na história que sabe produzi-lo, e responder ao pedido é a US 4.3.

  **A elegibilidade não mora neste changeset.** Ele vê uma linha, e as regras da
  troca — mesma função, evento futuro, alvo não escalado na origem — comparam
  quatro tabelas: vivem em `ChurchBands.Swaps`, antes do insert.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Schedule.EventBand

  @statuses [:pending, :cancelled]

  schema "swap_requests" do
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :requester_event_band, EventBand
    belongs_to :requester_member, BandMember
    belongs_to :target_event_band, EventBand
    belongs_to :target_member, BandMember

    timestamps(type: :utc_datetime)
  end

  @doc """
  Como se escreve o estado na tela.

  Não há um `statuses/0` ao lado, como `BandMember.types/0`: aquele existe
  porque o formulário monta o seletor de função a partir dele, e aqui nenhuma
  tela oferece o estado — quem o muda é o contexto.
  """
  def status_label(:pending), do: "Pendente"
  def status_label(:cancelled), do: "Cancelado"

  @doc """
  Changeset do pedido.

  As quatro chaves são obrigatórias e todas ganham `assoc_constraint/2`: elas
  chegam do contexto já resolvidas, e a constraint é a rede para a escala que
  sumiu entre a leitura e a gravação.

  A `unique_constraint/3` nomeia o índice **parcial** de um pendente por vaga de
  origem: quantos pedidos cancelados a pessoa quiser ter tentado antes, mas um
  só pendente por evento seu.
  """
  def changeset(swap_request, attrs) do
    swap_request
    |> cast(attrs, [
      :requester_event_band_id,
      :requester_member_id,
      :target_event_band_id,
      :target_member_id
    ])
    |> validate_required([
      :requester_event_band_id,
      :requester_member_id,
      :target_event_band_id,
      :target_member_id
    ])
    |> assoc_constraint(:requester_event_band)
    |> assoc_constraint(:requester_member)
    |> assoc_constraint(:target_event_band)
    |> assoc_constraint(:target_member)
    |> unique_constraint([:requester_event_band_id, :requester_member_id],
      name: :swap_requests_one_pending_per_slot_index,
      message: "Você já tem um pedido de troca pendente para este evento."
    )
  end
end
