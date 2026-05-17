defmodule ExPiWeb.PageController do
  use ExPiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
