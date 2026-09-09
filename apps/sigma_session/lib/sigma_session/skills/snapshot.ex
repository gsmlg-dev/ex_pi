defmodule Sigma.Session.Skills.Snapshot do
  @moduledoc "Builds bounded immutable local skill snapshots and tree digests."

  alias Sigma.Session.Skills.Skill

  @max_files 500
  @max_file_bytes 5 * 1024 * 1024
  @max_entry_bytes 256 * 1024

  @spec prepare(Skill.t()) :: {:ok, map()} | {:error, atom() | binary()}
  def prepare(%Skill{path: entry_path} = skill) when is_binary(entry_path) do
    root = Path.dirname(entry_path)

    with {:ok, files, _count} <- collect_files(root),
         {:ok, manifest} <- read_manifest(files),
         {:ok, entry_body} <- read_entry(entry_path) do
      {:ok,
       %{
         skill_id: skill.skill_id || skill.name,
         source_id: skill.source_id || to_string(skill.source),
         root: root,
         entry_body: instructions_body(entry_body),
         manifest: manifest,
         digest: %{scheme: "sha256-tree-v1", value: digest(manifest)},
         provenance: %{path: entry_path, source: skill.source}
       }}
    end
  end

  def prepare(_skill), do: {:error, :invalid_skill}

  defp collect_files(root), do: collect_files(root, "", [], 0)

  defp collect_files(_root, _relative, _files, count) when count > @max_files,
    do: {:error, :package_too_large}

  defp collect_files(root, relative, files, count) do
    directory = if relative == "", do: root, else: Path.join(root, relative)

    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce_while(Enum.sort(entries), {:ok, files, count}, fn entry, {:ok, acc, n} ->
          path = Path.join(directory, entry)
          rel = if relative == "", do: entry, else: Path.join(relative, entry)

          case File.lstat(path) do
            {:ok, %File.Stat{type: :symlink}} ->
              {:halt, {:error, :unsafe_archive}}

            {:ok, %File.Stat{type: :directory}} ->
              case collect_files(root, rel, acc, n) do
                {:ok, nested, nested_count} -> {:cont, {:ok, nested, nested_count}}
                {:error, _reason} = error -> {:halt, error}
              end

            {:ok, %File.Stat{type: :regular}} ->
              if File.stat!(path).size > @max_file_bytes,
                do: {:halt, {:error, :package_too_large}},
                else: {:cont, {:ok, [{rel, path} | acc], n + 1}}

            _ ->
              {:halt, {:error, :unsafe_archive}}
          end
        end)
        |> case do
          {:ok, files, count} -> {:ok, files, count}
          {:error, _reason} = error -> error
        end

      {:error, _reason} ->
        {:error, :resource_unavailable}
    end
  end

  defp read_manifest(files) do
    Enum.reduce_while(Enum.sort_by(files, &elem(&1, 0)), {:ok, []}, fn {relative, path},
                                                                       {:ok, acc} ->
      with {:ok, bytes} <- File.read(path),
           :ok <- validate_entry_size(relative, bytes) do
        entry = %{
          path: relative,
          sha256: digest_bytes(bytes),
          executable?: executable?(path),
          size: byte_size(bytes)
        }

        {:cont, {:ok, [entry | acc]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp read_entry(path) do
    case File.read(path) do
      {:ok, content} when byte_size(content) <= @max_entry_bytes -> {:ok, content}
      {:ok, _content} -> {:error, :entry_too_large}
      {:error, _reason} -> {:error, :resource_unavailable}
    end
  end

  defp instructions_body(content) do
    case String.split(String.replace(content, "\r\n", "\n"), "\n---\n", parts: 2) do
      ["---\n" <> _metadata, body] -> String.trim(body)
      _ -> String.trim(content)
    end
  end

  defp validate_entry_size("SKILL.md", bytes) when byte_size(bytes) <= @max_entry_bytes, do: :ok
  defp validate_entry_size("SKILL.md", _bytes), do: {:error, :entry_too_large}
  defp validate_entry_size(_path, _bytes), do: :ok

  defp executable?(path) do
    %File.Stat{mode: mode} = File.stat!(path)
    Bitwise.band(mode, 0o111) != 0
  end

  defp digest(manifest), do: manifest |> Enum.map_join("\n", &manifest_line/1) |> digest_bytes()

  defp manifest_line(entry) do
    Enum.join(
      [entry.path, entry.sha256, to_string(entry.executable?), to_string(entry.size)],
      "\t"
    )
  end

  defp digest_bytes(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
