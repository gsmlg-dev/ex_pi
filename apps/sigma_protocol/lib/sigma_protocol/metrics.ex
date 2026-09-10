defmodule Sigma.Protocol.Metrics do
  @moduledoc "Versioned, transport-neutral metrics DTOs shared by runtime clients."

  defmodule Turn do
    @moduledoc "Versioned durable turn lifecycle DTO."

    defstruct schema_version: 1,
              turn_id: nil,
              session_id: nil,
              status: :unknown,
              revision: 0,
              started_at: nil,
              finished_at: nil,
              wall_time_ms: nil,
              terminal_reason: nil,
              source_message_id: nil,
              source_checkpoint_id: nil,
              retry_of_turn_id: nil,
              provenance: nil

    @type t :: %__MODULE__{}
  end

  @version 1
  @purposes [:turn, :compaction, :auxiliary, :sampling]
  @statuses [:started, :running, :completed, :failed, :cancelled, :interrupted, :unknown]
  @usage_statuses [:reported, :derived, :estimated, :unknown]
  @provenance_values [
    :provider,
    :adapter,
    :reported,
    :derived,
    :estimated,
    :unknown,
    :input,
    :input_tokens,
    :prompt_tokens,
    :output,
    :output_tokens,
    :completion_tokens,
    :cache_read,
    :cache_read_tokens,
    :cache_write,
    :cache_write_tokens,
    :reasoning,
    :reasoning_tokens,
    :visible_output,
    :visible_output_tokens,
    :total_tokens,
    :included,
    :excluded,
    :subset
  ]
  @optional_strings [
    :message_id,
    :turn_id,
    :session_id,
    :origin_session_id,
    :provider,
    :model,
    :started_at,
    :finished_at,
    :retry_of
  ]
  @optional_counters [
    :input_tokens_total,
    :output_tokens_total,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :visible_output_tokens,
    :elapsed_ms,
    :first_output_ms,
    :ttft_ms
  ]
  @wire_fields [
    :request_id,
    :message_id,
    :turn_id,
    :session_id,
    :origin_session_id,
    :provider,
    :model,
    :purpose,
    :status,
    :revision,
    :started_at,
    :finished_at,
    :input_tokens_total,
    :output_tokens_total,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :visible_output_tokens,
    :elapsed_ms,
    :first_output_ms,
    :ttft_ms,
    :usage_status,
    :provenance,
    :retry_of
  ]
  @request_fact_fields [:schema_version | @wire_fields]
  @turn_optional_strings [
    :session_id,
    :started_at,
    :finished_at,
    :terminal_reason,
    :source_message_id,
    :source_checkpoint_id,
    :retry_of_turn_id
  ]
  @turn_wire_fields [
    :turn_id,
    :session_id,
    :status,
    :revision,
    :started_at,
    :finished_at,
    :wall_time_ms,
    :terminal_reason,
    :source_message_id,
    :source_checkpoint_id,
    :retry_of_turn_id,
    :provenance
  ]

  defstruct schema_version: @version,
            request_id: nil,
            message_id: nil,
            turn_id: nil,
            session_id: nil,
            origin_session_id: nil,
            provider: nil,
            model: nil,
            purpose: :turn,
            status: :unknown,
            revision: 0,
            started_at: nil,
            finished_at: nil,
            input_tokens_total: nil,
            output_tokens_total: nil,
            cache_read_tokens: nil,
            cache_write_tokens: nil,
            reasoning_tokens: nil,
            visible_output_tokens: nil,
            elapsed_ms: nil,
            first_output_ms: nil,
            ttft_ms: nil,
            usage_status: :unknown,
            provenance: nil,
            retry_of: nil

  @type request :: %__MODULE__{}
  @type turn :: Turn.t()

  def version, do: @version

  @doc "Builds a request DTO only when identity and revision are valid."
  def request(attrs) when is_map(attrs) do
    with :ok <- validate_version(value(attrs, :schema_version, @version)),
         request_id when is_binary(request_id) and request_id != "" <- value(attrs, :request_id),
         revision when is_integer(revision) and revision >= 0 <- value(attrs, :revision, 0),
         {:ok, purpose} <- enum(value(attrs, :purpose, :turn), @purposes, :purpose),
         {:ok, status} <- enum(value(attrs, :status, :unknown), @statuses, :status),
         {:ok, usage_status} <-
           enum(value(attrs, :usage_status, :unknown), @usage_statuses, :usage_status),
         :ok <- validate_optional_strings(attrs),
         :ok <- validate_optional_counters(attrs) do
      {:ok,
       struct(
         __MODULE__,
         @wire_fields
         |> Map.new(&{&1, value(attrs, &1)})
         |> Map.put(:request_id, request_id)
         |> Map.put(:revision, revision)
         |> Map.put(:purpose, purpose)
         |> Map.put(:status, status)
         |> Map.put(:usage_status, usage_status)
       )}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_request_identity}
    end
  end

  def request(_), do: {:error, :invalid_request}

  @doc "Drops fields outside the request metrics schema and sanitizes semantic provenance."
  def sanitize_request_fact(attrs) when is_map(attrs) do
    @request_fact_fields
    |> Enum.reduce(%{}, fn field, acc ->
      case fetch(attrs, field) do
        {:ok, value} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
    |> Map.update(:provenance, nil, &sanitize_provenance/1)
  end

  def sanitize_request_fact(_attrs), do: %{}

  @doc "Builds a durable turn lifecycle DTO with bounded status values."
  def turn(attrs) when is_map(attrs) do
    with :ok <- validate_version(value(attrs, :schema_version, @version)),
         turn_id when is_binary(turn_id) and turn_id != "" <- value(attrs, :turn_id),
         revision when is_integer(revision) and revision >= 0 <- value(attrs, :revision, 0),
         {:ok, status} <- enum(value(attrs, :status, :unknown), @statuses, :status),
         :ok <- validate_optional_strings(attrs, @turn_optional_strings, :invalid_turn),
         :ok <- validate_optional_counter(attrs, :wall_time_ms, :invalid_turn) do
      {:ok,
       struct(
         Turn,
         @turn_wire_fields
         |> Map.new(&{&1, value(attrs, &1)})
         |> Map.put(:turn_id, turn_id)
         |> Map.put(:revision, revision)
         |> Map.put(:status, status)
       )}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_turn_identity}
    end
  end

  def turn(_), do: {:error, :invalid_turn}

  @doc "Returns the bounded, string-keyed Protocol V1 representation."
  def to_map(%__MODULE__{} = request) do
    @wire_fields
    |> Map.new(fn field -> {Atom.to_string(field), wire_value(Map.fetch!(request, field))} end)
    |> Map.put("schemaVersion", request.schema_version)
  end

  def to_map(%Turn{} = turn) do
    @turn_wire_fields
    |> Map.new(fn field -> {Atom.to_string(field), wire_value(Map.fetch!(turn, field))} end)
    |> Map.put("schemaVersion", turn.schema_version)
  end

  defp validate_version(@version), do: :ok
  defp validate_version(version), do: {:error, {:unsupported_metrics_version, version}}

  defp validate_optional_strings(attrs) do
    validate_optional_strings(attrs, @optional_strings, :invalid_request)
  end

  defp validate_optional_strings(attrs, fields, error) do
    if Enum.all?(fields, fn field ->
         value = value(attrs, field)
         is_nil(value) or is_binary(value)
       end),
       do: :ok,
       else: {:error, error}
  end

  defp validate_optional_counters(attrs) do
    if Enum.all?(@optional_counters, fn field ->
         value = value(attrs, field)
         is_nil(value) or (is_integer(value) and value >= 0)
       end),
       do: :ok,
       else: {:error, :invalid_request}
  end

  defp validate_optional_counter(attrs, field, error) do
    value = value(attrs, field)
    if is_nil(value) or (is_integer(value) and value >= 0), do: :ok, else: {:error, error}
  end

  defp enum(value, allowed, _field) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_request}
  end

  defp enum(value, allowed, field) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:unknown_metrics_enum, field, value}}
      atom -> {:ok, atom}
    end
  end

  defp enum(value, _allowed, field), do: {:error, {:unknown_metrics_enum, field, value}}

  defp wire_value(nil), do: nil
  defp wire_value(value) when is_atom(value), do: Atom.to_string(value)
  defp wire_value(value), do: value

  defp sanitize_provenance(provenance) when is_map(provenance) do
    sanitized =
      for key <- [
            :source,
            :adapter,
            :input_tokens,
            :output_tokens,
            :cache_read_tokens,
            :cache_write_tokens,
            :reasoning_tokens,
            :visible_output_tokens,
            :total_tokens
          ],
          {:ok, value} <- [fetch(provenance, key)],
          safe_provenance_value?(value),
          into: %{},
          do: {key, value}

    if map_size(sanitized) == 0, do: nil, else: sanitized
  end

  defp sanitize_provenance(_provenance), do: nil

  defp safe_provenance_value?(value) when is_atom(value), do: value in @provenance_values

  defp safe_provenance_value?(value) when is_binary(value),
    do: Enum.any?(@provenance_values, &(Atom.to_string(&1) == value))

  defp safe_provenance_value?(_value), do: false

  defp fetch(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, Atom.to_string(key))
    end
  end

  defp value(attrs, key, default \\ nil)

  defp value(attrs, :schema_version, default),
    do: Map.get(attrs, :schema_version, Map.get(attrs, "schemaVersion", default))

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
