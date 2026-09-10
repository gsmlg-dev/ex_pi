defmodule Sigma.Ai.ProviderRequest do
  @moduledoc "Provider-neutral request passed to provider adapters."

  @enforce_keys [:model, :context]
  defstruct [
    :model,
    :context,
    :session_id,
    :log_session_id,
    :request_id,
    :message_id,
    :turn_id,
    :origin_session_id,
    :purpose,
    :status,
    :started_at,
    :finished_at,
    :elapsed_ms,
    :first_output_ms,
    :ttft_ms,
    :usage,
    :usage_revision,
    :retry_of,
    monotonic_started_at: nil,
    options: []
  ]

  @type t :: %__MODULE__{
          model: map(),
          context: map(),
          options: keyword(),
          session_id: String.t() | nil,
          log_session_id: String.t() | nil,
          request_id: String.t() | nil,
          message_id: String.t() | nil,
          turn_id: String.t() | nil,
          origin_session_id: String.t() | nil,
          purpose: atom() | String.t() | nil,
          status: atom() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          elapsed_ms: non_neg_integer() | nil,
          first_output_ms: non_neg_integer() | nil,
          ttft_ms: non_neg_integer() | nil,
          usage: Sigma.Ai.ProviderUsage.t() | nil,
          usage_revision: non_neg_integer(),
          retry_of: String.t() | nil
        }

  @doc "Creates a provider attempt with a stable identity for its lifetime."
  def new(params) when is_map(params) do
    model = Map.fetch!(params, :model)
    context = Map.fetch!(params, :context)

    %__MODULE__{
      model: model,
      context: context,
      options: Map.get(params, :options, []),
      session_id: Map.get(params, :session_id),
      log_session_id: Map.get(params, :log_session_id, Map.get(params, :session_id)),
      request_id: Map.get(params, :request_id) || request_id(),
      message_id: Map.get(params, :message_id),
      turn_id: Map.get(params, :turn_id),
      origin_session_id: Map.get(params, :origin_session_id, Map.get(params, :session_id)),
      purpose: Map.get(params, :purpose, :turn),
      status: :running,
      started_at: Map.get(params, :started_at),
      usage: Map.get(params, :usage),
      usage_revision: Map.get(params, :usage_revision, 0),
      retry_of: Map.get(params, :retry_of)
    }
  end

  @doc "Records a monotonic start boundary; wall time remains caller supplied."
  def begin(
        %__MODULE__{} = request,
        monotonic_now \\ System.monotonic_time(:millisecond),
        wall_time \\ nil
      )
      when is_integer(monotonic_now) do
    %{
      request
      | monotonic_started_at: monotonic_now,
        started_at: wall_time || request.started_at,
        status: :running
    }
  end

  @doc "Marks the first provider output, ignoring keepalive/empty events."
  def mark_output(request, monotonic_now, kind \\ :output)

  def mark_output(%__MODULE__{} = request, monotonic_now, kind)
      when is_integer(monotonic_now) and kind in [:output, :text, :thinking, :tool_arguments] do
    elapsed = elapsed_from(request, monotonic_now)
    first = request.first_output_ms || elapsed
    ttft = if kind == :text, do: request.ttft_ms || elapsed, else: request.ttft_ms
    %{request | first_output_ms: first, ttft_ms: ttft}
  end

  def mark_output(%__MODULE__{} = request, monotonic_now, kind)
      when is_integer(monotonic_now) and kind in [:keepalive, :empty],
      do: request

  @doc "Marks terminal state and derives elapsed time from monotonic boundaries."
  def finish(
        %__MODULE__{} = request,
        status,
        monotonic_now \\ System.monotonic_time(:millisecond),
        wall_time \\ nil
      )
      when is_atom(status) and is_integer(monotonic_now) do
    %{
      request
      | status: status,
        elapsed_ms: elapsed_from(request, monotonic_now),
        finished_at: wall_time
    }
  end

  @doc "Applies a current or newer usage report without changing request lifecycle state."
  def put_usage(
        %__MODULE__{usage_revision: current_revision} = request,
        %Sigma.Ai.ProviderUsage{usage_revision: revision} = usage
      )
      when revision >= current_revision do
    %{request | usage: usage, usage_revision: revision}
  end

  def put_usage(%__MODULE__{} = request, %Sigma.Ai.ProviderUsage{}), do: request

  def from_legacy(params) when is_map(params) do
    %__MODULE__{
      model: Map.fetch!(params, :model),
      context: Map.fetch!(params, :context),
      options: Map.get(params, :options, []),
      session_id: Map.get(params, :session_id),
      log_session_id: Map.get(params, :log_session_id, Map.get(params, :session_id)),
      request_id: Map.get(params, :request_id),
      message_id: Map.get(params, :message_id),
      turn_id: Map.get(params, :turn_id),
      origin_session_id: Map.get(params, :origin_session_id),
      purpose: Map.get(params, :purpose),
      status: Map.get(params, :status),
      started_at: Map.get(params, :started_at),
      finished_at: Map.get(params, :finished_at),
      usage: Map.get(params, :usage),
      usage_revision: Map.get(params, :usage_revision, 0),
      retry_of: Map.get(params, :retry_of),
      elapsed_ms: Map.get(params, :elapsed_ms),
      first_output_ms: Map.get(params, :first_output_ms),
      ttft_ms: Map.get(params, :ttft_ms)
    }
  end

  def to_legacy(%__MODULE__{} = request) do
    %{
      model: request.model,
      context: request.context,
      options: request.options,
      session_id: request.session_id,
      log_session_id: request.log_session_id,
      request_id: request.request_id,
      message_id: request.message_id,
      turn_id: request.turn_id,
      origin_session_id: request.origin_session_id,
      purpose: request.purpose,
      status: request.status,
      started_at: request.started_at,
      finished_at: request.finished_at,
      elapsed_ms: request.elapsed_ms,
      first_output_ms: request.first_output_ms,
      ttft_ms: request.ttft_ms,
      usage: request.usage,
      usage_revision: request.usage_revision,
      retry_of: request.retry_of
    }
  end

  defp elapsed_from(%__MODULE__{monotonic_started_at: nil}, _), do: nil
  defp elapsed_from(%__MODULE__{monotonic_started_at: started}, now), do: max(now - started, 0)

  defp request_id do
    "req_" <> (:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false))
  end
end
