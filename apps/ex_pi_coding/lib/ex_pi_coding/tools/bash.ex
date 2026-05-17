defmodule ExPiCoding.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.
  """
  @behaviour ExPiCoding.Tool

  @impl true
  def name, do: "bash"

  @impl true
  def description do
    "Execute a bash command in the current working directory. Returns stdout and stderr. Optionally provide a timeout in seconds."
  end

  @impl true
  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "command" => %{
          "type" => "string",
          "description" => "Bash command to execute"
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "Timeout in seconds (optional, no default timeout)"
        }
      },
      "required" => ["command"]
    }
  end

  @impl true
  def execute(_tool_call_id, params, opts) do
    command = Map.get(params, "command")
    timeout = Map.get(params, "timeout")
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    on_update = Keyword.get(opts, :on_update)
    signal = Keyword.get(opts, :signal)

    timeout_ms = if timeout && timeout > 0, do: timeout * 1000, else: :infinity

    if File.dir?(cwd) do
      # Use a Task to manage the Port and stream data back.
      task =
        Task.async(fn ->
          # Use /bin/sh -c to support shell built-ins and proper command execution
          port =
            Port.open({:spawn, "/bin/sh -c " <> quote_command(command)}, [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              cd: cwd
            ])

          collect_output(port, [], on_update)
        end)

      wait_for_task(task, signal, timeout_ms, command)
    else
      {:error, "Working directory does not exist: #{cwd}\nCannot execute bash commands."}
    end
  end

  defp quote_command(command) do
    # Simple quoting for /bin/sh -c
    "'" <> String.replace(command, "'", "'\\''") <> "'"
  end

  defp collect_output(port, acc, on_update) do
    receive do
      {^port, {:data, data}} ->
        new_acc = [data | acc]

        if on_update do
          on_update.(%{
            content: [%{type: :text, text: Enum.join(Enum.reverse(new_acc), "")}],
            details: %{status: :running}
          })
        end

        collect_output(port, new_acc, on_update)

      {^port, {:exit_status, status}} ->
        %{exit_code: status, output: Enum.join(Enum.reverse(acc), "")}
    end
  end

  defp wait_for_task(task, signal, timeout_ms, command) do
    receive do
      {task_ref, result} when task_ref == task.ref ->
        Process.demonitor(task_ref, [:flush])

        {:ok,
         %{
           content: [%{type: :text, text: result.output}],
           details: %{exit_code: result.exit_code, command: command}
         }}

      {:abort, ^signal} when signal != nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, "Command aborted"}

      {:DOWN, task_ref, :process, _pid, reason} when task_ref == task.ref ->
        {:error, "Bash tool process crashed: #{inspect(reason)}"}
    after
      timeout_ms ->
        Task.shutdown(task, :brutal_kill)
        {:error, "Command timed out after #{timeout_ms / 1000} seconds"}
    end
  end
end
