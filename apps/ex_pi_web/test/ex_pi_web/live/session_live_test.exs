defmodule ExPiWeb.SessionLiveTest do
  use ExPiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "renders session page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/sessions/test")
    assert html =~ "Type a message..."
  end

  test "submits prompt", %{conn: conn} do
    Phoenix.PubSub.subscribe(ExPiWeb.PubSub, "session:test")
    {:ok, view, _html} = live(conn, "/sessions/test")
    
    render_submit(view, "send_prompt", %{"prompt" => "hello"})
    
    assert_receive {:agent_start}, 2000
    assert_receive {:turn_start}, 2000
    assert_receive {:message_start, %{role: :user, content: "hello"}}, 2000
    assert_receive {:message_end, %{role: :assistant}}, 2000
  end

  test "handles permission request", %{conn: conn} do
    # We need a mock provider that triggers a tool call
    # The MockProvider in session_live.ex currently doesn't trigger tool calls by default
    # But wait, I'll just manually broadcast the permission request to the view
    
    {:ok, view, _html} = live(conn, "/sessions/test")
    
    tool_call = %{id: "tc1", name: "bash", arguments: %{"command" => "rm -rf /"}}
    Phoenix.PubSub.broadcast(ExPiWeb.PubSub, "session:test", {:permission_request, self(), tool_call})
    
    assert render(view) =~ "Permission Required"
    assert render(view) =~ "rm -rf /"
    
    render_click(view, "permission_allow")
    
    assert_receive {:permission_response, :allow}
    refute render(view) =~ "Permission Required"
  end
end
