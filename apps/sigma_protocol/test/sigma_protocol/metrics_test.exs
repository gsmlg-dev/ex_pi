defmodule Sigma.Protocol.MetricsTest do
  use ExUnit.Case, async: true

  alias Sigma.Protocol.{Codec, Envelope, Metrics}

  test "builds a bounded request DTO with stable identity and revision" do
    assert {:ok, %Metrics{request_id: "req-1", revision: 2, output_tokens_total: 10}} =
             Metrics.request(%{"request_id" => "req-1", "revision" => 2, output_tokens_total: 10})
  end

  test "rejects missing or negative request identity" do
    assert {:error, :invalid_request_identity} = Metrics.request(%{})

    assert {:error, :invalid_request_identity} =
             Metrics.request(%{request_id: "req-1", revision: -1})
  end

  test "round trips a string-keyed metrics DTO through Protocol V1 JSON" do
    wire = %{
      "schemaVersion" => 1,
      "request_id" => "req-wire",
      "message_id" => "message-1",
      "turn_id" => "turn-1",
      "session_id" => "session-1",
      "origin_session_id" => "parent-session",
      "provider" => "anthropic",
      "model" => "opus",
      "purpose" => "turn",
      "status" => "completed",
      "revision" => 3,
      "started_at" => "2026-09-09T10:00:00Z",
      "finished_at" => "2026-09-09T10:00:01Z",
      "input_tokens_total" => 120,
      "output_tokens_total" => 30,
      "cache_read_tokens" => 100,
      "cache_write_tokens" => 0,
      "reasoning_tokens" => 10,
      "visible_output_tokens" => 20,
      "elapsed_ms" => 1_000,
      "first_output_ms" => 20,
      "ttft_ms" => 25,
      "usage_status" => "reported",
      "provenance" => %{"provider" => "test"},
      "retry_of" => nil
    }

    assert {:ok, request} = Metrics.request(wire)
    assert Metrics.to_map(request) == wire

    assert {:ok, event} =
             Envelope.event("session.snapshot", "session-1", %{"metrics" => wire},
               id: "metrics-event",
               timestamp: 1
             )

    assert {:ok, encoded} = Codec.encode(event)
    assert {:ok, decoded} = Codec.decode(encoded)
    assert {:ok, ^request} = Metrics.request(decoded.payload["metrics"])
  end

  test "rejects unsupported versions and enums without creating atoms" do
    unknown_status = "future_metrics_status_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_status) end

    assert {:error, {:unsupported_metrics_version, 2}} =
             Metrics.request(%{"schemaVersion" => 2, "request_id" => "req-1"})

    assert {:error, {:unknown_metrics_enum, :status, ^unknown_status}} =
             Metrics.request(%{"request_id" => "req-1", "status" => unknown_status})

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_status) end
  end

  test "rejects negative counters instead of treating unknown usage as zero" do
    assert {:error, :invalid_request} =
             Metrics.request(%{"request_id" => "req-1", "input_tokens_total" => -1})

    assert {:ok, request} = Metrics.request(%{"request_id" => "req-2"})
    assert request.input_tokens_total == nil
    assert request.output_tokens_total == nil
  end

  test "accepts auxiliary request purpose while retaining sampling compatibility" do
    assert {:ok, %Metrics{purpose: :auxiliary}} =
             Metrics.request(%{"request_id" => "req-aux", "purpose" => "auxiliary"})

    assert {:ok, %Metrics{purpose: :sampling}} =
             Metrics.request(%{"request_id" => "req-sampling", "purpose" => "sampling"})
  end

  test "round trips a versioned durable turn lifecycle DTO" do
    wire = %{
      "schemaVersion" => 1,
      "turn_id" => "turn-1",
      "session_id" => "session-1",
      "status" => "completed",
      "revision" => 2,
      "started_at" => "2026-09-09T10:00:00Z",
      "finished_at" => "2026-09-09T10:00:03Z",
      "wall_time_ms" => 3_000,
      "terminal_reason" => "stop",
      "source_message_id" => "message-1",
      "source_checkpoint_id" => "checkpoint-1",
      "retry_of_turn_id" => "turn-0",
      "provenance" => %{"source" => "agent"}
    }

    assert {:ok, %Metrics.Turn{} = turn} = Metrics.turn(wire)
    assert Metrics.to_map(turn) == wire
  end

  test "rejects invalid turn identity, counters, and unknown status without creating atoms" do
    unknown = "future_turn_status_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    assert {:error, :invalid_turn_identity} = Metrics.turn(%{})
    assert {:error, :invalid_turn} = Metrics.turn(%{turn_id: "turn-1", wall_time_ms: -1})

    assert {:error, {:unknown_metrics_enum, :status, ^unknown}} =
             Metrics.turn(%{"turn_id" => "turn-1", "status" => unknown})

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end
end
