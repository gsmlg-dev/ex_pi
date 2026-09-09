defmodule Sigma.Agent.SkillInvocation do
  @moduledoc "Pure validation, fingerprinting, and state transitions for skill invocations."

  @states ~w(preparing queued running completed failed cancelled interrupted)a
  @terminal_states ~w(completed failed cancelled interrupted)a
  @max_arguments 16 * 1024

  @spec new(map()) :: {:ok, map()} | {:error, atom()}
  def new(attrs) when is_map(attrs) do
    with {:ok, request} <- validate_request(attrs),
         fingerprint <- fingerprint(request) do
      {:ok,
       Map.merge(request, %{
         request_id: attrs["request_id"] || attrs[:request_id] || random_id(),
         request_key: attrs["request_key"] || attrs[:request_key],
         fingerprint: fingerprint,
         state: :preparing
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_invocation}

  @spec transition(map(), atom()) :: {:ok, map()} | {:error, atom()}
  def transition(%{state: state} = invocation, next_state) when next_state in @states do
    if next_state in allowed_transitions(state) do
      {:ok, %{invocation | state: next_state}}
    else
      {:error, :invalid_state_transition}
    end
  end

  def transition(_invocation, _next_state), do: {:error, :invalid_state_transition}

  def terminal?(%{state: state}), do: state in @terminal_states
  def terminal?(_invocation), do: false

  defp validate_request(attrs) do
    repository_id = value(attrs, :repository_id, "repositoryId")
    session_id = value(attrs, :session_id, "sessionId")
    skill_id = value(attrs, :skill_id, "skillId")
    reference = value(attrs, :reference, "reference")
    arguments = value(attrs, :arguments, "arguments") || ""
    mode = value(attrs, :mode, "mode") || "next_turn"

    cond do
      not valid_string?(repository_id) or not valid_string?(session_id) -> {:error, :invalid_scope}
      (valid_string?(skill_id) and valid_string?(reference)) or not (valid_string?(skill_id) or valid_string?(reference)) ->
        {:error, :invalid_skill_reference}
      not is_binary(arguments) or byte_size(arguments) > @max_arguments -> {:error, :arguments_too_large}
      mode != "next_turn" -> {:error, :unsupported_mode}
      true ->
        {:ok,
         %{
           repository_id: repository_id,
           session_id: session_id,
           skill_id: skill_id,
           reference: reference,
           arguments: arguments,
           mode: :next_turn,
           expected_digest: value(attrs, :expected_digest, "expectedDigest")
         }}
    end
  end

  defp fingerprint(request) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(Map.take(request, [:repository_id, :session_id, :skill_id, :reference, :arguments, :mode, :expected_digest])))
    |> Base.encode16(case: :lower)
  end

  defp allowed_transitions(:preparing), do: [:queued, :running, :completed, :failed, :cancelled, :interrupted]
  defp allowed_transitions(:queued), do: [:running, :cancelled, :interrupted]
  defp allowed_transitions(:running), do: [:completed, :failed, :cancelled, :interrupted]
  defp allowed_transitions(_state), do: []

  defp value(attrs, atom_key, string_key), do: Map.get(attrs, atom_key, Map.get(attrs, string_key))
  defp valid_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp random_id, do: "inv_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
end
