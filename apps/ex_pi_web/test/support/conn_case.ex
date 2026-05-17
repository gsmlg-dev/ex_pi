defmodule ExPiWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import ExPiWeb.ConnCase

      alias ExPiWeb.Router.Helpers, as: Routes

      @endpoint ExPiWeb.Endpoint
      use ExPiWeb, :verified_routes
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
