defmodule Ret.Application do
  use Application
  import Cachex.Spec

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    :ok = Ret.Statix.connect()

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      supervisor(Ret.Repo, []),

      #supervisor(RetWeb.Endpoint, []),
      #supervisor(RetWeb.Presence, []),

      # Quantum scheduler
      worker(Ret.Scheduler, []),
      # Quantum singleton scheduler
      worker(Ret.SingletonScheduler, []),
      # Storage for rate limiting
      worker(PlugAttack.Storage.Ets, [RetWeb.RateLimit.Storage, [clean_period: 60_000]]),
      # Media resolution cache
      worker(
        Cachex,
        [
          :media_urls,
          [
            expiration: expiration(default: :timer.minutes(5)),
            fallback: fallback(default: &Ret.MediaResolver.resolve/1)
          ]
        ],
        id: :media_url_cache
      ),

      # Page origin chunk cache
      worker(
        Cachex,
        [
          :page_chunks,
          [
            warmers: [warmer(module: Ret.PageOriginWarmer)]
          ]
        ],
        id: :page_chunk_cache
      ),

      # Runs Discord bot
      worker(HubsBotManager, []),

      # Graceful shutdown
      supervisor(TheEnd.Of.Phoenix, [[timeout: 10_000, endpoint: RetWeb.Endpoint]])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ret.Supervisor]
    :ok = :error_logger.add_report_handler(Sentry.Logger)
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    RetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
