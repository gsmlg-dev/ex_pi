defmodule ExPiCoding do
  @moduledoc """
  Main entry point for the ExPiCoding application.
  Starts the dispatcher supervisor.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExPiCoding.Dispatcher
    ]

    opts = [strategy: :one_for_one, name: ExPiCoding.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
