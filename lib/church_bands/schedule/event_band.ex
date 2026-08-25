defmodule ChurchBands.Schedule.EventBand do
  @moduledoc """
  Uma banda escalada num evento (US 3.4).

  É a linha que liga o calendário às bandas, e o registro mais consultado da
  fase: é dela que saem "quem toca neste culto", "onde a minha banda precisa
  estar" (US 3.5) e o set daquela banda naquele evento (US 3.6).

  **A escala não guarda quem escalou.** A permissão de mexer num evento se lê
  do estado atual — o tipo continuar marcado e uma banda liderada continuar
  escalada —, e não da autoria; por isso nem o evento nem esta linha carregam
  `created_by_id`. Quem perde a banda da escala perde o evento junto, e isso é
  proposital.

  **A janela de conflito de 3 horas não mora aqui.** Um changeset olha uma
  linha só, e a janela compara o `starts_at` de eventos diferentes: quem a
  aplica é `ChurchBands.Schedule.schedule_band/2`, antes de inserir.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias ChurchBands.Bands.Band
  alias ChurchBands.Schedule.Event

  schema "event_bands" do
    belongs_to :event, Event
    belongs_to :band, Band

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset da escala.

  A duplicata é recusada pelo índice único do par, e não por uma consulta
  antes: a lista de candidatas já esconde as bandas que o evento tem, então
  quem chega aqui com uma repetida forçou o formulário — e é o banco que tem a
  palavra final. Mesmo arranjo de `Repertoire.BandRepertoire`.
  """
  def changeset(event_band, attrs) do
    event_band
    |> cast(attrs, [:event_id, :band_id])
    |> validate_required([:band_id], message: "escolha a banda")
    |> validate_required([:event_id])
    |> assoc_constraint(:band)
    # O evento vem do socket, nunca do formulário: se ele não existisse, a tela
    # não teria aberto. Por isso só a banda ganha `assoc_constraint/2`.
    |> unique_constraint([:event_id, :band_id],
      name: :event_bands_event_id_band_id_index,
      message: "esta banda já está escalada neste evento"
    )
  end
end
