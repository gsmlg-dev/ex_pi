defmodule ExPiWeb.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: ExPiWeb.PubSub},
      ExPiWeb.SessionManager,
      ExPiWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ExPiWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExPiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
