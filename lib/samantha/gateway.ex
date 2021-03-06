defmodule Samantha.Gateway do
  @moduledoc """
  This module is specifically used for handling the queue of gateway messages
  that are meant to be send. The queue is managed by `Samantha.Queue`, which 
  also supports named queues beyond the gateway queue.
  """

  use GenServer
  require Logger

  # API

  def start_link(parent_pid) do
    GenServer.start_link __MODULE__, %{
      parent_pid: parent_pid,
    }
  end

  def update_seq(pid, num) do
    GenServer.cast pid, {:seq, num}
  end

  # Server

  def handle_info(:poll_gateway, state) do
    try do
      msg = GenServer.call Samantha.Queue, {:pop, "gateway"}
      unless is_nil msg do
        Logger.info "[GATEWAY] Got gateway op send req.: #{inspect msg}"
        msg = msg |> Poison.decode!
        case Hammer.check_rate("gateway_msg", 60_000, 100) do
          {:allow, _count} ->
            # send
            payload = msg |> :erlang.term_to_binary
            WebSockex.send_frame state[:parent_pid], {:binary, payload}
            Logger.info "[GATEWAY] Sent op #{inspect msg["op"]}!"
          {:deny, _limit} -> 
            # re-queue
            Logger.info "[GATEWAY] Re-queued: #{inspect msg}"
            GenServer.cast Samantha.Queue, {:push, "gateway", msg}
        end
      end
    rescue
      e -> 
        Sentry.capture_exception e, [stacktrace: System.stacktrace()]
        Logger.warn "Exception! #{inspect e, pretty: true} - #{inspect System.stacktrace(), pretty: true}"
    end
    Process.send_after self(), :poll_gateway, 100
    {:noreply, state}
  end

  def handle_cast({:seq, num}, state) do
    {:noreply, %{state | seq: num}}
  end

  def init(state) do
    {:ok, state}
  end
end