defmodule Sigma.Session.SkillInvocationStore do
  @moduledoc "Atomic session-scoped persistence for skill invocation records."

  alias Sigma.Session.SessionFiles

  @spec list(binary(), binary()) :: {:ok, [map()]} | {:error, term()}
  def list(sessions_dir, session_id) do
    with {:ok, path} <- path(sessions_dir, session_id) do
      case File.read(path) do
        {:ok, content} -> decode(content)
        {:error, :enoent} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec find(binary(), binary(), binary()) :: {:ok, map() | nil} | {:error, term()}
  def find(sessions_dir, session_id, request_key) do
    with {:ok, records} <- list(sessions_dir, session_id) do
      {:ok, Enum.find(records, &(&1["requestKey"] == request_key))}
    end
  end

  @spec reserve(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def reserve(sessions_dir, session_id, record) when is_map(record) do
    with_lock(sessions_dir, session_id, fn -> reserve_locked(sessions_dir, session_id, record) end)
  end

  defp reserve_locked(sessions_dir, session_id, record) do
    with {:ok, records} <- list(sessions_dir, session_id),
         :ok <- validate_record(record),
         nil <- Enum.find(records, &(&1["requestKey"] == record["requestKey"])),
         {:ok, path} <- path(sessions_dir, session_id),
         :ok <- write(path, records ++ [record]) do
      {:ok, record}
    else
      %{} -> {:error, :idempotency_conflict}
      {:error, _reason} = error -> error
    end
  end

  @spec update(binary(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def update(sessions_dir, session_id, invocation_id, changes) when is_map(changes) do
    with_lock(sessions_dir, session_id, fn -> update_locked(sessions_dir, session_id, invocation_id, changes) end)
  end

  @spec recover(binary(), binary()) :: {:ok, [map()]} | {:error, term()}
  def recover(sessions_dir, session_id) do
    with_lock(sessions_dir, session_id, fn ->
      with {:ok, records} <- list(sessions_dir, session_id),
           recovered <-
             Enum.map(records, fn record ->
               if record["state"] in ["preparing", "queued", "running"],
                 do: Map.put(record, "state", "interrupted"),
                 else: record
             end),
           {:ok, path} <- path(sessions_dir, session_id),
           :ok <- write(path, recovered) do
        {:ok, recovered}
      end
    end)
  end

  defp update_locked(sessions_dir, session_id, invocation_id, changes) do
    with {:ok, records} <- list(sessions_dir, session_id),
         {record, rest} when is_map(record) <- take_record(records, invocation_id),
         updated <- Map.merge(record, changes),
         {:ok, path} <- path(sessions_dir, session_id),
         :ok <- write(path, [updated | rest]) do
      {:ok, updated}
    else
      nil -> {:error, :invocation_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp take_record(records, id) do
    case Enum.split_with(records, &(&1["invocationId"] == id)) do
      {[record], rest} -> {record, rest}
      _ -> nil
    end
  end

  defp validate_record(record) do
    if Enum.all?(["invocationId", "requestKey", "fingerprint", "state"], &is_binary(record[&1])) do
      :ok
    else
      {:error, :invalid_invocation_record}
    end
  end

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, records} when is_list(records) ->
        if Enum.all?(records, &is_map/1), do: {:ok, records}, else: {:error, :invalid_invocation_store}

      _ -> {:error, :invalid_invocation_store}
    end
  end

  defp write(path, records) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, content} <- Jason.encode(records),
         :ok <- File.write(temporary, content),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp path(sessions_dir, session_id) do
    with {:ok, jsonl_path} <- SessionFiles.jsonl_path(sessions_dir, session_id) do
      {:ok, jsonl_path <> ".skill-invocations.json"}
    end
  end

  defp with_lock(sessions_dir, session_id, fun) do
    table = lock_table()
    key = {sessions_dir, session_id}

    if :ets.insert_new(table, {key, self()}) do
      try do
        fun.()
      after
        :ets.delete(table, key)
      end
    else
      receive do
      after
        1 -> with_lock(sessions_dir, session_id, fun)
      end
    end
  end

  defp lock_table do
    case :ets.whereis(:sigma_skill_invocation_locks) do
      :undefined ->
        try do
          :ets.new(:sigma_skill_invocation_locks, [:named_table, :set, :public])
        rescue
          ArgumentError -> :sigma_skill_invocation_locks
        end

      _table ->
        :sigma_skill_invocation_locks
    end
  end
end
