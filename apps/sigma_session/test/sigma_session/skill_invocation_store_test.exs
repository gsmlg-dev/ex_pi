defmodule Sigma.Session.SkillInvocationStoreTest do
  use ExUnit.Case, async: true

  alias Sigma.Session.SkillInvocationStore

  @tag :tmp_dir
  test "reserves, reads, and updates invocation records", %{tmp_dir: tmp_dir} do
    record = %{
      "invocationId" => "inv-1",
      "requestKey" => "key-1",
      "fingerprint" => "fp-1",
      "state" => "preparing"
    }

    assert {:ok, ^record} = SkillInvocationStore.reserve(tmp_dir, "session-1", record)
    assert {:ok, ^record} = SkillInvocationStore.find(tmp_dir, "session-1", "key-1")
    assert {:error, :idempotency_conflict} = SkillInvocationStore.reserve(tmp_dir, "session-1", record)
    assert {:ok, updated} = SkillInvocationStore.update(tmp_dir, "session-1", "inv-1", %{"state" => "queued"})
    assert updated["state"] == "queued"
  end

  @tag :tmp_dir
  test "serializes concurrent reservations for one request key", %{tmp_dir: tmp_dir} do
    record = %{"invocationId" => "inv-concurrent", "requestKey" => "same", "fingerprint" => "fp", "state" => "preparing"}
    results = 1..2 |> Enum.map(fn _ -> Task.async(fn -> SkillInvocationStore.reserve(tmp_dir, "session-1", record) end) end) |> Enum.map(&Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :idempotency_conflict}, &1)) == 1
  end

  @tag :tmp_dir
  test "marks nonterminal records interrupted during recovery", %{tmp_dir: tmp_dir} do
    record = %{"invocationId" => "inv-recover", "requestKey" => "key", "fingerprint" => "fp", "state" => "running"}
    assert {:ok, _} = SkillInvocationStore.reserve(tmp_dir, "session-1", record)
    assert {:ok, [recovered]} = SkillInvocationStore.recover(tmp_dir, "session-1")
    assert recovered["state"] == "interrupted"
  end
end
