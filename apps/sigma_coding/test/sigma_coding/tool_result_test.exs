defmodule Sigma.Coding.ToolResultTest do
  use ExUnit.Case, async: true

  alias Sigma.Coding.ToolError
  alias Sigma.Coding.ToolResult

  describe "normalize/1 for transport failure markers" do
    test "wraps {:transport_failure, ...} into a ToolError with kind :transport_failure" do
      data = %{original_reason: :timeout}
      marker = {:transport_failure, "Send Failure", "mcp__hub__echo", "hub", data}

      assert {:error, %ToolError{kind: :transport_failure, message: msg, details: details}} =
               ToolResult.normalize(marker)

      assert msg == "Send Failure"
      assert details.tool_name == "mcp__hub__echo"
      assert details.server_id == "hub"
      assert details.data == data
    end

    test "preserves the renderable transport failure message" do
      marker = {:transport_failure, "Send Failure", "echo", "hub", %{original_reason: :closed}}

      assert {:error, %ToolError{message: "Send Failure"}} = ToolResult.normalize(marker)
    end
  end

  describe "normalize/1 fall-through" do
    test "still rejects unknown shapes" do
      assert {:error, %ToolError{kind: :malformed_result}} =
               ToolResult.normalize({:something_weird, 42})
    end

    test "still passes through successful tool results" do
      result = %{content: [%{type: :text, text: "hi"}], details: %{}, is_error: false}
      assert {:ok, %ToolResult{}} = ToolResult.normalize({:ok, result})
    end
  end
end
