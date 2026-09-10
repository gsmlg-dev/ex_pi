defmodule Sigma.Agent.MetricsPrivacyTest do
  use ExUnit.Case, async: true

  alias Sigma.Agent.ProtocolEventMapper
  alias Sigma.Protocol.Codec

  test "protocol request metrics expose only allowlisted fields and semantic provenance" do
    secret = "sk-protocol-secret"

    attrs = %{
      request_id: "request-1",
      turn_id: "turn-1",
      revision: 1,
      status: :completed,
      output_tokens_total: 3,
      headers: %{"authorization" => "Bearer #{secret}"},
      api_key: secret,
      raw_payload: %{"response" => secret},
      provenance: %{
        source: :provider,
        output_tokens: :output_tokens,
        headers: %{"x-api-key" => secret},
        adapter: secret
      }
    }

    {event, "turn-1"} =
      ProtocolEventMapper.map(
        {:metrics, :request_finished, attrs},
        "session-1",
        "turn-1"
      )

    assert event.payload["data"]["provenance"] == %{
             "source" => "provider",
             "output_tokens" => "output_tokens"
           }

    refute Map.has_key?(event.payload["data"], "headers")
    refute Map.has_key?(event.payload["data"], "api_key")
    refute Map.has_key?(event.payload["data"], "raw_payload")

    assert {:ok, json} = Codec.encode(event)
    refute json =~ secret
    refute json =~ "authorization"
    refute json =~ "raw_payload"
  end
end
