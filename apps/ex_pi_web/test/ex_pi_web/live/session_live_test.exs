defmodule ExPiWeb.SessionLiveTest do
  use ExPiWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @workdir "/tmp/pi-test"
  @encoded_workdir Base.url_encode64(@workdir)

  setup do
    File.mkdir_p!(@workdir)
    on_exit(fn -> File.rm_rf!(@workdir) end)
    :ok
  end

  test "renders session page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workdir/#{@encoded_workdir}/sessions/test")
    assert html =~ "Ask π anything..."
  end

  test "submits prompt", %{conn: conn} do
    Phoenix.PubSub.subscribe(ExPiWeb.PubSub, "session:test")
    {:ok, view, _html} = live(conn, "/workdir/#{@encoded_workdir}/sessions/test")
    
    render_submit(view, "send_prompt", %{"prompt" => "hello"})
    
    assert_receive {:agent_start, _}, 2000
    assert_receive {:turn_start}, 2000
    assert_receive {:message_start, %{role: :user, content: "hello"}}, 2000
    assert_receive {:message_end, %{role: :assistant}}, 2000
  end

  test "handles permission request", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workdir/#{@encoded_workdir}/sessions/test")
    
    tool_call = %{id: "tc1", name: "bash", arguments: %{"command" => "rm -rf /"}}
    Phoenix.PubSub.broadcast(ExPiWeb.PubSub, "session:test", {:permission_request, self(), tool_call})
    
    assert render(view) =~ "Security Interceptor"
    assert render(view) =~ "rm -rf /"
    
    render_click(view, "permission_allow")
    
    assert_receive {:permission_response, :allow}
    refute render(view) =~ "Security Interceptor"
  end
end
