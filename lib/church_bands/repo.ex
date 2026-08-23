defmodule ChurchBands.Repo do
  use Ecto.Repo,
    otp_app: :church_bands,
    adapter: Ecto.Adapters.Postgres
end
