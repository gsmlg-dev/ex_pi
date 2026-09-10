defmodule Sigma.Session.ContextCompactionReplayTest do
  use ExUnit.Case, async: true

  alias Sigma.Session.{Log, Metrics, Writer}

  @tag :tmp_dir
  test "rebuilds usage and committed compaction after context decreases", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "context-compaction.jsonl")

    {:ok, writer} =
      Writer.start_link(storage_id: path, session_id: "writer", cwd: "/repo")

    assert {:ok, _header_id} = Writer.append(writer, {:agent_start, "/repo"})
    assert {:ok, header_snapshot} = Log.snapshot(path)
    session_id = header_snapshot.session_id

    facts = [
      {:turn_started,
       %{
         turn_id: "turn-before-compaction",
         session_id: session_id,
         revision: 0,
         status: :running,
         started_at: "2026-09-09T08:00:00Z"
       }},
      {:request_finished,
       %{
         request_id: "turn-request",
         turn_id: "turn-before-compaction",
         session_id: session_id,
         purpose: :turn,
         revision: 1,
         status: :completed,
         usage_status: :reported,
         input_tokens_total: 100_000,
         output_tokens_total: 2_000,
         elapsed_ms: 2_000,
         started_at: "2026-09-09T08:00:00Z",
         finished_at: "2026-09-09T08:00:02Z"
       }},
      {:turn_finished,
       %{
         turn_id: "turn-before-compaction",
         session_id: session_id,
         revision: 1,
         status: :completed,
         started_at: "2026-09-09T08:00:00Z",
         finished_at: "2026-09-09T08:00:02Z",
         wall_time_ms: 2_000
       }},
      {:request_finished,
       %{
         request_id: "compaction-request",
         session_id: session_id,
         purpose: :compaction,
         revision: 1,
         status: :completed,
         usage_status: :reported,
         input_tokens_total: 100_000,
         output_tokens_total: 5_000,
         elapsed_ms: 3_000,
         started_at: "2026-09-09T08:01:00Z",
         finished_at: "2026-09-09T08:01:03Z"
       }},
      {:compaction,
       %{
         compaction_id: "compaction-1",
         revision: 0,
         status: :started,
         trigger: :automatic,
         before_tokens: 100_000,
         before_source: :provider_usage,
         started_at: "2026-09-09T08:01:00Z"
       }},
      {:compaction,
       %{
         compaction_id: "compaction-1",
         revision: 1,
         status: :committed,
         trigger: :automatic,
         request_ids: ["compaction-request"],
         before_tokens: 100_000,
         after_tokens: 25_000,
         before_source: :provider_usage,
         after_source: :estimated,
         started_at: "2026-09-09T08:01:00Z",
         finished_at: "2026-09-09T08:01:03Z"
       }},
      {:request_finished,
       %{
         request_id: "legacy-request",
         turn_id: "legacy-turn",
         session_id: session_id,
         purpose: :turn,
         revision: 1,
         status: :completed
       }}
    ]

    Enum.each(facts, fn fact ->
      assert {:ok, _entry_id} = Writer.append(writer, fact)
    end)

    assert {:ok, first_snapshot} = Log.snapshot(path)
    first_projection = Metrics.snapshot(first_snapshot.metrics)

    assert %{input_tokens_total: 100_000, total_tokens: 102_000} =
             first_projection.turns["turn-before-compaction"]

    assert %{input_tokens_total: 100_000, total_tokens: 105_000} =
             first_projection.usage_by_purpose.compaction

    assert %{total_tokens: 207_000, partial?: true} = first_projection.own_usage
    assert first_projection.coverage == %{known: 2, total: 3, ratio: 2 / 3}

    assert %{total_tokens: nil, input_tokens_total: nil, partial?: true} =
             first_projection.turns["legacy-turn"]

    assert first_projection.successful_compactions == 1

    assert %{
             status: :committed,
             before_tokens: 100_000,
             after_tokens: 25_000,
             request_ids: ["compaction-request"]
           } = first_projection.last_compaction

    GenServer.stop(writer)

    assert {:ok, restarted_writer} =
             Writer.start_link(storage_id: path, session_id: session_id, cwd: "/repo")

    assert {:ok, _writer_state} = Writer.flush(restarted_writer)
    assert {:ok, rebuilt_snapshot} = Log.snapshot(path)
    rebuilt_projection = Metrics.snapshot(rebuilt_snapshot.metrics)

    assert rebuilt_projection == first_projection
    assert rebuilt_projection.own_usage.total_tokens == 207_000
    assert rebuilt_projection.successful_compactions == 1
    assert rebuilt_projection.last_compaction.after_tokens == 25_000
  end
end
