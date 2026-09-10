defmodule Sigma.Web.SessionObservabilityTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Sigma.Web.SessionObservability

  test "renders complete message metrics and unknown values explicitly" do
    html =
      render_component(&SessionObservability.message_metrics_footer/1, %{
        metrics: %{input_tokens_total: 10, output_tokens_total: 20, throughput: 2.5},
        elapsed_ms: 100,
        status: :completed
      })

    assert html =~ "input: 10"
    assert html =~ "output: 20"
    assert html =~ "2.50 tok/s"
    assert html =~ "100ms"

    assert render_component(&SessionObservability.message_metrics_footer/1, %{metrics: %{}}) =~
             "unknown"
  end

  test "renders context stale state and accessible actions" do
    html =
      render_component(&SessionObservability.context_budget_card/1, %{
        policy: %{
          estimate: 90_000,
          estimate_source: :last_request_measurement,
          tokens_remaining: 0,
          threshold: 80_000,
          estimate_stale: true
        }
      })

    assert html =~ "estimate stale"
    assert html =~ "last_request_measurement"
    actions = render_component(&SessionObservability.action_bar/1, %{})
    assert actions =~ "aria-label=\"Retry turn\""
    assert actions =~ "aria-label=\"Fork session\""
  end

  test "renders durable session scopes, timing, and compaction details" do
    html =
      render_component(&SessionObservability.session_overview_rail/1, %{
        snapshot: %{
          status: :idle,
          model: "claude-test",
          started_at: "2026-09-09T08:00:00Z",
          own_usage: %{
            input_tokens_total: 40_000,
            output_tokens_total: 1_000,
            total_tokens: 41_000,
            throughput: 50.25
          },
          inherited_usage: %{total_tokens: 3_000, request_count: 2},
          parent_session_id: "parent-session",
          coverage: %{known: 2, total: 3},
          context: 25_000,
          successful_compactions: 1,
          last_compaction: %{
            before_tokens: 100_000,
            after_tokens: 25_000,
            finished_at: "2026-09-09T08:05:00Z"
          }
        }
      })

    assert html =~ "input: 40000"
    assert html =~ "output: 1000"
    assert html =~ "known total: 41000"
    assert html =~ "coverage: 2/3"
    assert html =~ "inherited: 3000 tokens (2 requests)"
    assert html =~ "forked from: parent-session"
    assert html =~ "50.25 tok/s"
    assert html =~ "100000 -&gt; 25000"
  end

  test "renders a turn total with request and tool counts" do
    html =
      render_component(&SessionObservability.turn_summary/1, %{
        summary: %{
          request_count: 2,
          tool_count: 1,
          input_tokens_total: 50,
          output_tokens_total: 20,
          throughput: 4.0
        }
      })

    assert html =~ "Turn total"
    assert html =~ "requests: 2"
    assert html =~ "tools: 1"
    assert html =~ "input: 50"
    assert html =~ "output: 20"
  end

  test "renders original and replacement branch answers with provenance" do
    html =
      render_component(&SessionObservability.branch_alternatives/1, %{
        branches: [
          %{
            leaf_id: "replacement-leaf",
            active?: true,
            branch_point_id: "prompt-entry",
            turn_id: "turn-replacement",
            retry_of_turn_id: "turn-original",
            last_user: %{message_id: "retry-user", text: "Investigate again"},
            last_assistant: %{message_id: "replacement-answer", text: "Replacement answer"}
          },
          %{
            leaf_id: "original-leaf",
            active?: false,
            branch_point_id: "prompt-entry",
            turn_id: "turn-after-original",
            retry_of_turn_id: nil,
            last_user: %{message_id: "original-user", text: "Investigate"},
            last_assistant: %{message_id: "original-answer", text: "Original answer"}
          }
        ]
      })

    assert html =~ "Alternative executions"
    assert html =~ "Active execution"
    assert html =~ "Original execution"
    assert html =~ "Replacement answer"
    assert html =~ "Original answer"
    assert html =~ "turn-original"
    assert html =~ "prompt-entry"
  end
end
