defmodule ChurchBands.Swaps.SwapRequest do
  @moduledoc """
  Um pedido de troca de escala (US 4.2).

  **O pedido é de vaga para vaga, não de pessoa para pessoa.** A linha guarda as
  duas escalas (`event_bands`) e os dois vínculos (`band_members`) — nunca
  `user_id`. Quem é a pessoa se lê do vínculo; qual o evento, da escala. É o que
  faz o pedido morrer sozinho quando a banda sai da escala ou a pessoa sai da
  banda, pelo `on_delete: :delete_all` das quatro chaves, sem nenhuma limpeza
  escrita à mão.

  **`status` e `mode` ficam fora do `cast/3`.** Quem os muda são as funções de
  resposta do contexto, por `change/2` — o mesmo cuidado do `status` do `Event`
  (US 3.2) e do `active` do instrumento (US 2.8): um parâmetro forjado no
  formulário não aceita troca pela porta dos fundos.

  **`:accepted` e `:declined` nascem na US 4.3**, e não na 4.2: cada estado
  entra na história que sabe produzi-lo, porque a cobertura é 100% e valor de
  enum que nenhum caminho alcança é ramo morto. É a mesma razão de `mode` só
  existir agora — antes de haver resposta, não havia modo de resposta.

  **`mode` só tem valor em pedido aceito.** Ele diz o alcance do aceite:
  `:cover` é o alvo assumindo o dia de quem pediu e mantendo o seu; `:swap` é
  as duas vagas mudando de dono. Pendente, cancelado e recusado têm `nil` — e
  é por isso que quem escreve o estado na tela é `status_label/1`, que lê os
  dois campos juntos.

  **A troca aceita não vira linha de escala.** Ela continua sendo exceção sobre
  o elenco derivado da US 4.1: nada em `band_members` muda, e desfazer a troca
  é a escala deixar de existir — o `on_delete: :delete_all` das quatro chaves.

  **A elegibilidade não mora neste changeset.** Ele vê uma linha, e as regras da
  troca — mesma função, evento futuro, alvo não escalado na origem — comparam
  quatro tabelas: vivem em `ChurchBands.Swaps`, antes do insert.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Schedule.EventBand

  @statuses [:pending, :cancelled, :accepted, :declined]
  @modes [:cover, :swap]

  schema "swap_requests" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :mode, Ecto.Enum, values: @modes
    field :responded_at, :utc_datetime

    belongs_to :requester_event_band, EventBand
    belongs_to :requester_member, BandMember
    belongs_to :target_event_band, EventBand
    belongs_to :target_member, BandMember

    timestamps(type: :utc_datetime)
  end

  @doc """
  Como se escreve o estado na tela.

  Recebe o **pedido**, e não o `status`, porque o aceite não se escreve sem o
  modo: <q>Aceito — cobrir</q> e <q>Aceito — troca</q> são estados diferentes
  para quem lê a lista, e são a mesma linha de `status`. Os outros três
  ignoram `mode`, que neles é `nil`.

  Não há um `statuses/0` ao lado, como `BandMember.types/0`: aquele existe
  porque o formulário monta o seletor de função a partir dele, e aqui nenhuma
  tela oferece o estado — quem o muda é o contexto.
  """
  def status_label(%__MODULE__{status: :pending}), do: "Pendente"
  def status_label(%__MODULE__{status: :cancelled}), do: "Cancelado"
  def status_label(%__MODULE__{status: :declined}), do: "Recusado"
  def status_label(%__MODULE__{status: :accepted, mode: :cover}), do: "Aceito — cobrir"
  def status_label(%__MODULE__{status: :accepted, mode: :swap}), do: "Aceito — troca"

  @doc """
  O modo que chegou do `phx-value` da tela, ou `:error`.

  O modo **vem do botão**, e quem sabe disso o forja sem botão nenhum: a
  conversão é a peneira, e é ela que faz qualquer outro texto ser recusado
  antes de gravar coisa nenhuma. Fica aqui, e não no contexto, porque a lista
  de modos é deste schema — `String.to_existing_atom/1` aceitaria `:banana`
  por já existir em outro lugar do sistema.
  """
  def cast_mode(mode) when is_binary(mode) do
    Enum.find_value(@modes, :error, &(to_string(&1) == mode && {:ok, &1}))
  end

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
