defmodule Sigma.Session.Skills.Parser do
  @moduledoc "Pure YAML frontmatter extraction for Agent Skills."

  @spec parse(binary()) :: {:ok, map()} | {:error, binary()}
  def parse(content) when is_binary(content) do
    content
    |> normalize_newlines()
    |> extract_frontmatter()
    |> decode()
  end

  defp normalize_newlines(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  defp extract_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [metadata, _body] -> {:ok, metadata}
      _ -> {:error, "frontmatter closing delimiter is missing"}
    end
  end

  defp extract_frontmatter(_content), do: {:ok, ""}
  defp decode({:ok, ""}), do: {:ok, %{}}

  defp decode({:ok, metadata}) do
    with :ok <- reject_duplicate_keys(metadata),
         {:ok, value} <- YamlElixir.read_from_string(metadata) do
      if is_map(value), do: {:ok, value}, else: {:error, "frontmatter must be a mapping"}
    else
      {:error, error} when is_exception(error) ->
        {:error, "invalid frontmatter: #{Exception.message(error)}"}

      {:error, _reason} = error -> error
    end
  end

  defp decode({:error, _reason} = error), do: error

  defp reject_duplicate_keys(metadata) do
    try do
      metadata
      |> :yamerl_constr.string(
        detailed_constr: true,
        str_node_as_binary: true,
        keep_duplicate_keys: true
      )
      |> Enum.find_value(:ok, &duplicate_keys_in_document/1)
    catch
      _kind, _reason -> {:error, "invalid frontmatter"}
    end
  end

  defp duplicate_keys_in_document({:yamerl_doc, node}), do: duplicate_keys_in_node(node)
  defp duplicate_keys_in_document(_document), do: :ok

  defp duplicate_keys_in_node({:yamerl_map, _module, _tag, _location, pairs}) do
    keys = Enum.map(pairs, fn {key, _value} -> node_value(key) end)

    case Enum.find(keys, fn key -> Enum.count(keys, &(&1 == key)) > 1 end) do
      nil -> Enum.find_value(pairs, :ok, fn {_key, value} -> duplicate_keys_in_node(value) end)
      key -> {:error, "duplicate frontmatter key: #{key}"}
    end
  end

  defp duplicate_keys_in_node({:yamerl_seq, _module, _tag, _location, values}),
    do: Enum.find_value(values, :ok, &duplicate_keys_in_node/1)

  defp duplicate_keys_in_node(_node), do: :ok

  defp node_value({_type, _module, _tag, _location, value}), do: value
end
