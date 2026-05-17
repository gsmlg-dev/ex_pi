defmodule ExPiWeb.SessionManager do
  @moduledoc """
  Manages ExPiAgent processes for web sessions.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_agent(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_agent, session_id, opts})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{agents: %{}}}
  end

  @impl true
  def handle_call({:get_agent, session_id, opts}, _from, state) do
    case Map.get(state.agents, session_id) do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          start_agent(session_id, opts, state)
        end

      nil ->
        start_agent(session_id, opts, state)
    end
  end

  defp start_agent(session_id, opts, state) do
    case ExPiAgent.start_link(opts) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, put_in(state.agents[session_id], pid)}

      error ->
        {:reply, error, state}
    end
  end
end
