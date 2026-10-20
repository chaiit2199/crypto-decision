defmodule CryptoDecisionLab.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CryptoDecisionLabWeb.Telemetry,
      CryptoDecisionLab.Repo,
      {DNSCluster,
       query: Application.get_env(:crypto_decision_lab, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CryptoDecisionLab.PubSub},
      {Oban, Application.fetch_env!(:crypto_decision_lab, Oban)},
      {Task.Supervisor, name: CryptoDecisionLab.TaskSupervisor},
      CryptoDecisionLab.MarketData.Poller,
      Supervisor.child_spec(
        {CryptoDecisionLab.MarketData.Poller,
         name: CryptoDecisionLab.MarketData.SourcePoller,
         bootstrap: false,
         run: &CryptoDecisionLab.MarketData.SourceSync.enqueue_coinbase/0},
        id: CryptoDecisionLab.MarketData.SourcePoller
      ),
      Supervisor.child_spec(
        {CryptoDecisionLab.MarketData.Poller,
         name: CryptoDecisionLab.MarketData.GoldSourcePoller,
         bootstrap: false,
         interval:
           Application.get_env(
             :crypto_decision_lab,
             :gold_price_poll_interval_ms,
             900_000
           ),
         run: &CryptoDecisionLab.MarketData.SourceSync.enqueue_gold/0},
        id: CryptoDecisionLab.MarketData.GoldSourcePoller
      ),
      # Start to serve requests, typically the last entry
      CryptoDecisionLabWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CryptoDecisionLab.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CryptoDecisionLabWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
