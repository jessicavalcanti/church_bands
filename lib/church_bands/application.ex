defmodule ChurchBands.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TwMerge.Cache,
      ChurchBandsWeb.Telemetry,
      ChurchBands.Repo,
      {DNSCluster, query: Application.get_env(:church_bands, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ChurchBands.PubSub},
      ChurchBands.RateLimit,
      # Start a worker by calling: ChurchBands.Worker.start_link(arg)
      # {ChurchBands.Worker, arg},
      # Start to serve requests, typically the last entry
      ChurchBandsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChurchBands.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChurchBandsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
