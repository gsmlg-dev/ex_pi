defmodule Sigma.Ai.ProviderUsage do
  @moduledoc "Provider-neutral token and cache usage without invented values."

  @provenance_keys [
    :source,
    :adapter,
    :input_tokens,
    :output_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :visible_output_tokens,
    :total_tokens
  ]
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

  defstruct [
    :input_tokens,
    :output_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :total_tokens,
    :reasoning_tokens,
    :visible_output_tokens,
    usage_status: :unknown,
    usage_revision: 0,
    provenance: nil
  ]

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          cache_read_tokens: non_neg_integer() | nil,
          cache_write_tokens: non_neg_integer() | nil,
          total_tokens: non_neg_integer() | nil,
          reasoning_tokens: non_neg_integer() | nil,
          visible_output_tokens: non_neg_integer() | nil,
          usage_status: :reported | :derived | :estimated | :unknown,
          usage_revision: non_neg_integer(),
          provenance: term()
        }

  def from_map(nil), do: nil

  def from_map(usage) when is_map(usage) do
    normalize(usage)
  end

  @doc "Normalizes provider-specific counters without inventing missing values."
  def normalize(usage) when is_map(usage) do
    input =
      first_value(usage, [:input, :input_tokens, :prompt_tokens, "input_tokens", "prompt_tokens"])

    output =
      first_value(usage, [
        :output,
        :output_tokens,
        :completion_tokens,
        "output_tokens",
        "completion_tokens"
      ])

    cache_read =
      first_value(usage, [:cache_read, :cache_read_tokens, "cache_read_tokens"]) ||
        get_in(usage, ["input_token_details", "cached_tokens"])

    cache_write = first_value(usage, [:cache_write, :cache_write_tokens, "cache_write_tokens"])

    reasoning =
      first_value(usage, [:reasoning, :reasoning_tokens, "reasoning_tokens"]) ||
        get_in(usage, ["output_token_details", "reasoning_tokens"])

    visible =
      first_value(usage, [:visible_output, :visible_output_tokens, "visible_output_tokens"])

    total = first_value(usage, [:total_tokens, "total_tokens"])

    total =
      if is_nil(total) and is_integer(input) and is_integer(output),
        do: input + output,
        else: total

    fields = [input, output, cache_read, cache_write, total]
    status = usage_status(input, output, fields)

    %__MODULE__{
      input_tokens: input,
      output_tokens: output,
      cache_read_tokens: cache_read,
      cache_write_tokens: cache_write,
      total_tokens: total,
      reasoning_tokens: reasoning,
      visible_output_tokens: visible,
      usage_status: status,
      usage_revision: value(usage, :usage_revision) || value(usage, :revision) || 0,
      provenance: sanitize_provenance(value(usage, :provenance) || value(usage, :source))
    }
  end

  def normalize(_), do: nil

  def complete?(%__MODULE__{usage_status: :reported}), do: true
  def complete?(_), do: false

  @doc "Keeps only bounded semantic provenance; transport metadata and payloads are discarded."
  def sanitize_provenance(provenance) when is_map(provenance) do
    sanitized =
      Enum.reduce(@provenance_keys, %{}, fn key, acc ->
        with value when not is_nil(value) <- value(provenance, key),
             {:ok, value} <- provenance_value(value) do
          Map.put(acc, key, value)
        else
          _unknown_or_unsafe -> acc
        end
      end)

    if map_size(sanitized) == 0, do: nil, else: sanitized
  end

  def sanitize_provenance(provenance) do
    case provenance_value(provenance) do
      {:ok, value} -> %{source: value}
      :error -> nil
    end
  end

  @doc "Returns the canonical fact shape consumed by session metrics."
  def to_fact(%__MODULE__{} = usage) do
    %{
      input_tokens_total: usage.input_tokens,
      output_tokens_total: usage.output_tokens,
      cache_read_tokens: usage.cache_read_tokens,
      cache_write_tokens: usage.cache_write_tokens,
      reasoning_tokens: usage.reasoning_tokens,
      visible_output_tokens: usage.visible_output_tokens,
      usage_status: usage.usage_status,
      usage_revision: usage.usage_revision,
      provenance: usage.provenance
    }
  end

  defp usage_status(input, output, fields) do
    cond do
      is_integer(input) and is_integer(output) -> :reported
      Enum.any?(fields, &is_integer/1) or not is_nil(input) or not is_nil(output) -> :derived
      true -> :unknown
    end
  end

  defp first_value(map, keys), do: Enum.find_value(keys, &Map.get(map, &1))

  defp provenance_value(value) when is_atom(value) do
    if value in @provenance_values, do: {:ok, value}, else: :error
  end

  defp provenance_value(value) when is_binary(value) do
    case Enum.find(@provenance_values, &(Atom.to_string(&1) == value)) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  defp provenance_value(_value), do: :error

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
