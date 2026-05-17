defmodule ExPiCoding.Utils.PathUtils do
  @moduledoc """
  Utilities for path resolution and safety checks.
  """

  @doc """
  Resolves a path relative to the given cwd and ensures it's within the cwd.

  ## Parameters
  - `path`: The path to resolve.
  - `cwd`: The current working directory.

  ## Returns
  - `{:ok, resolved_path}`: The path is within the cwd.
  - `{:error, reason}`: The path is outside the cwd or invalid.
  """
  def safe_resolve(path, cwd) do
    cwd = Path.expand(cwd)
    resolved_path = Path.expand(path, cwd)

    if within_cwd?(resolved_path, cwd) do
      {:ok, resolved_path}
    else
      {:error, "Access denied: Path '#{path}' is outside of the current working directory '#{cwd}'."}
    end
  end

  defp within_cwd?(path, cwd) do
    # Ensure cwd ends with a separator for prefix check
    cwd_prefix =
      if String.ends_with?(cwd, "/") do
        cwd
      else
        cwd <> "/"
      end

    path == cwd or String.starts_with?(path, cwd_prefix)
  end
end
