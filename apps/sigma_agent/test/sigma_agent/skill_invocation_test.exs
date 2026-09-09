defmodule Sigma.Agent.SkillInvocationTest do
  use ExUnit.Case, async: true

  alias Sigma.Agent.SkillInvocation

  @request %{
    "repositoryId" => "repo-1",
    "sessionId" => "session-1",
    "reference" => "global:review",
    "arguments" => "inspect"
  }

  test "validates and fingerprints equivalent requests deterministically" do
    assert {:ok, first} = SkillInvocation.new(@request)
    assert {:ok, second} = SkillInvocation.new(@request)
    assert first.fingerprint == second.fingerprint
    assert first.state == :preparing
    assert is_binary(first.request_id)
  end

  test "requires exactly one skill reference" do
    assert {:error, :invalid_skill_reference} =
             SkillInvocation.new(Map.put(@request, "skillId", "skill-1"))

    assert {:error, :invalid_skill_reference} =
             SkillInvocation.new(Map.delete(@request, "reference"))
  end

  test "enforces invocation state transitions" do
    assert {:ok, invocation} = SkillInvocation.new(@request)
    assert {:ok, queued} = SkillInvocation.transition(invocation, :queued)
    assert {:ok, running} = SkillInvocation.transition(queued, :running)
    assert {:ok, completed} = SkillInvocation.transition(running, :completed)
    assert SkillInvocation.terminal?(completed)
    assert {:error, :invalid_state_transition} = SkillInvocation.transition(completed, :running)
  end
end
