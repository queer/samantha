defmodule Samantha.Application do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec
    children = [
      {Lace.Redis, %{redis_ip: "127.0.0.1", redis_port: 6379, pool_size: 10, redis_pass: "a"}},
      {Lace, %{name: "node_name", group: "group_name", cookie: "node_cookie"}},
      # Set up our dynamic supervisor
      {Samantha.InternalSupervisor, [], name: Samantha.InternalSupervisor},
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    # Start the "real" supervisor
    app_sup = Supervisor.start_link(children, opts)
    # Start the shard worker under our dynamic supervisor
    {:ok, shard_pid} = Samantha.InternalSupervisor.start_child worker(Samantha.Shard, [%{token: System.get_env("BOT_TOKEN"), shard_count: 1}], name: Samantha.Shard)

    :timer.sleep 1000
    Logger.info "!"
    # Make the shard connect
    GenServer.cast shard_pid, :gateway_connect
    Logger.warn "Should be connecting!"
    #
    #Logger.info "Done?"
    app_sup
  end
end
