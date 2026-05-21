defmodule PiWeb.SettingsLiveTest do
  use PiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "system prompt markdown editor ignores LiveView patches", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/system_prompt")

    assert html =~ ~s(id="system-prompt-editor")
    assert html =~ ~s(phx-update="ignore")
  end
end
