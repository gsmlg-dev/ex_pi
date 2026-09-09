defmodule Sigma.Agent.SkillInvocationService do
  @moduledoc "Shared local skill invocation adapter for public transports."

  alias Sigma.Protocol.Envelope
  alias Sigma.Agent.Runtime

  def callbacks(context) when is_map(context) do
    %{
      skill_invoke: &invoke(&1, context),
      skill_invocation_status: &status(&1, context),
      skill_invocation_cancel: &cancel(&1, context)
    }
  end

  def invoke(payload, context) when is_map(payload) and is_map(context) do
    session_id = payload["sessionId"] || context[:session_id]
    request_key = payload["requestKey"] || context[:request_key]
    with true <- is_binary(request_key) and request_key != "",
         {:ok, request} <- Sigma.Agent.SkillInvocation.new(Map.merge(payload, %{"sessionId" => session_id, "request_key" => request_key})),
         {:ok, existing} <- store_find(context, session_id, request_key) do
      result =
        cond do
          existing && existing["fingerprint"] != request.fingerprint -> {:error, :idempotency_conflict}
          existing -> existing
          true -> reserve_and_admit(request, context)
        end

      invocation_event(result, session_id)
    else
      false -> {:error, :idempotency_key_required}
      {:error, reason} -> {:error, reason}
    end
  end

  def status(payload, context) do
    session_id = payload["sessionId"] || context[:session_id]

    with {:ok, records} <- store_list(context, session_id),
         record when is_map(record) <- Enum.find(records, &(&1["invocationId"] == payload["invocationId"])) do
      invocation_event(record, session_id)
    else
      nil -> {:error, :invocation_not_found}
      {:error, _reason} = error -> error
    end
  end

  def cancel(payload, context) do
    session_id = payload["sessionId"] || context[:session_id]

    with {:ok, record} <-
           store_update(context, session_id, payload["invocationId"], %{"state" => "cancelled"}) do
      invocation_event(record, session_id)
    end
  end

  defp reserve_and_admit(request, context) do
    record = %{
      "invocationId" => request.request_id,
      "requestKey" => request.request_key,
      "fingerprint" => request.fingerprint,
      "state" => "preparing",
      "repositoryId" => request.repository_id,
      "sessionId" => request.session_id,
      "skillId" => request.skill_id,
      "reference" => request.reference,
      "arguments" => request.arguments
    }

    with {:ok, _record} <- store_reserve(context, request.session_id, record),
         agent when is_pid(agent) <- Runtime.lookup(context[:repo_path], request.session_id, :agent),
         {:ok, expanded} <- expand_skill(context, request),
         result <- Sigma.Agent.follow_up(agent, expanded),
         state <- (if match?({:accepted, _}, result), do: "running", else: "queued"),
         {:ok, updated} <- store_update(context, request.session_id, request.request_id, %{"state" => state}) do
      updated
    else
      nil -> {:error, :session_not_running}
      {:error, _reason} = error -> error
    end
  end

  defp invocation_event({:error, reason}, _session_id), do: {:error, reason}

  defp invocation_event(record, session_id) when is_map(record) do
    Envelope.event("skill.invocation.updated", session_id, record, turn_id: record["turnId"])
  end

  defp store_find(context, session_id, request_key), do: store_call(context, :find, [session_id, request_key])
  defp store_list(context, session_id), do: store_call(context, :list, [session_id])
  defp store_reserve(context, session_id, record), do: store_call(context, :reserve, [session_id, record])
  defp store_update(context, session_id, invocation_id, changes), do: store_call(context, :update, [session_id, invocation_id, changes])

  defp store_call(context, operation, args) do
    case context[:skill_invocation_store] do
      %{^operation => callback} when is_function(callback) -> apply(callback, args)
      _ -> {:error, :skill_store_unavailable}
    end
  end

  defp expand_skill(context, request) do
    case context[:skill_expander] do
      callback when is_function(callback, 2) -> callback.("/skill #{request.reference || request.skill_id} #{request.arguments}", cwd: context[:repo_path])
      _ -> {:error, :skill_expander_unavailable}
    end
  end
end
