defmodule Sigma.Web.SessionObservability do
  use Sigma.Web, :html

  attr(:metrics, :map, required: true)
  attr(:elapsed_ms, :integer, default: nil)
  attr(:status, :atom, default: nil)

  def message_metrics_footer(assigns) do
    ~H"""
    <footer class="sigma-message-metrics mt-2 flex flex-wrap gap-x-3 gap-y-1 font-mono text-[10px] text-on-surface-variant" aria-label="Message metrics">
      <span>input: {metric_value(@metrics, :input_tokens_total)}</span>
      <span>output: {metric_value(@metrics, :output_tokens_total)}</span>
      <span>LLM: {throughput(@metrics)}</span>
      <span>elapsed: {duration(@elapsed_ms)}</span>
      <span :if={@status} class={status_class(@status)}>{status_label(@status)}</span>
      <details class="basis-full text-on-surface-variant">
        <summary class="w-fit cursor-pointer">Request details</summary>
        <dl class="mt-1 grid grid-cols-[auto_minmax(0,1fr)] gap-x-2 gap-y-1 pl-2">
          <dt>provider/model</dt>
          <dd class="break-all">{provider_model(@metrics)}</dd>
          <dt>first output</dt>
          <dd>{duration(value(@metrics, :first_output_ms))}</dd>
          <dt>TTFT</dt>
          <dd>{duration(value(@metrics, :ttft_ms))}</dd>
          <dt>cache read/write</dt>
          <dd>{metric_value(@metrics, :cache_read_tokens)} / {metric_value(@metrics, :cache_write_tokens)}</dd>
          <dt>reasoning/visible</dt>
          <dd>{metric_value(@metrics, :reasoning_tokens)} / {metric_value(@metrics, :visible_output_tokens)}</dd>
          <dt>purpose</dt>
          <dd>{display(value(@metrics, :purpose), "unknown")}</dd>
          <dt>data quality</dt>
          <dd>{display(value(@metrics, :usage_status), "unknown")}</dd>
        </dl>
      </details>
    </footer>
    """
  end

  attr(:summary, :map, required: true)

  def turn_summary(assigns) do
    ~H"""
    <section class="sigma-turn-summary border-t border-outline-variant pt-2 text-xs text-on-surface-variant" aria-label="Turn summary">
      <strong class="mr-2 text-on-surface">Turn total</strong>
      <span class="mr-2">requests: {@summary[:request_count] || 0}</span>
      <span class="mr-2">tools: {@summary[:tool_count] || 0}</span>
      <span class="mr-2">input: {metric_value(@summary, :input_tokens_total)}</span>
      <span class="mr-2">output: {metric_value(@summary, :output_tokens_total)}</span>
      <span class="mr-2">total: {metric_value(@summary, :total_tokens)}</span>
      <span class="mr-2">wall: {duration(value(@summary, :wall_time_ms))}</span>
      <span class="mr-2">LLM: {throughput(@summary)}</span>
      <span class={status_class(value(@summary, :status))}>
        {status_label(value(@summary, :status))}
      </span>
      <span :if={value(@summary, :terminal_reason)} class="ml-2 text-error">
        {display(value(@summary, :terminal_reason), "")}
      </span>
    </section>
    """
  end

  attr(:snapshot, :map, required: true)

  def session_overview_rail(assigns) do
    ~H"""
    <aside class="sigma-session-overview grid gap-3 text-sm" aria-label="Session observability">
      <section>
        <h2 class="text-xs font-semibold">Runtime</h2>
        <p>{display(value(@snapshot, :status), "unknown")}</p>
        <p class="text-xs text-on-surface-variant">model: {display(value(@snapshot, :model), "unknown")}</p>
      </section>
      <section>
        <h2 class="text-xs font-semibold">Usage</h2>
        <p>input: {usage_value(@snapshot, :input_tokens_total)}</p>
        <p>output: {usage_value(@snapshot, :output_tokens_total)}</p>
        <p>known total: {usage_total(@snapshot)}</p>
        <p class="text-xs text-on-surface-variant">{coverage(@snapshot)}</p>
        <p :if={inherited_requests(@snapshot) > 0} class="text-xs text-on-surface-variant">
          inherited: {inherited_total(@snapshot)} tokens ({inherited_requests(@snapshot)} requests)
        </p>
        <details :if={usage_groups(@snapshot, :usage_by_purpose) != []} class="mt-1 text-xs text-on-surface-variant">
          <summary class="cursor-pointer">By purpose</summary>
          <p :for={{name, usage} <- usage_groups(@snapshot, :usage_by_purpose)} class="font-mono">
            {name}: {metric_value(usage, :total_tokens)}
          </p>
        </details>
        <details :if={model_groups(@snapshot) != []} class="mt-1 text-xs text-on-surface-variant">
          <summary class="cursor-pointer">By model{if length(model_groups(@snapshot)) > 1, do: " · mixed models"}</summary>
          <p :for={group <- model_groups(@snapshot)} class="font-mono break-all">
            {provider_model(group)}: {metric_value(group.usage, :total_tokens)}
          </p>
        </details>
      </section>
      <section>
        <h2 class="text-xs font-semibold">Timing</h2>
        <p :if={value(@snapshot, :started_at)}>
          <time
            id={"session-started-#{value(@snapshot, :session_id) || "unknown"}"}
            phx-hook="RelativeTime"
            data-ts={timestamp_ms(value(@snapshot, :started_at))}
          >
            started: {display(value(@snapshot, :started_at), "unknown")}
          </time>
        </p>
        <p :if={is_nil(value(@snapshot, :started_at))}>started: unknown</p>
        <p>active: {duration(value(@snapshot, :active_time_ms))}</p>
        <p :if={value(@snapshot, :current_request)} class="text-xs text-on-surface-variant">
          current request:
          <span
            id="current-request-elapsed"
            phx-hook="ElapsedTime"
            data-ts={timestamp_ms(value(value(@snapshot, :current_request), :started_at))}
          >running</span>
        </p>
        <p>average LLM: {throughput(value(@snapshot, :own_usage) || %{})}</p>
      </section>
      <section>
        <h2 class="text-xs font-semibold">Context</h2>
        <p>{display(value(@snapshot, :context), "unknown")}</p>
      </section>
      <section>
        <h2 class="text-xs font-semibold">Compaction</h2>
        <p>successful: {display(value(@snapshot, :successful_compactions), "unknown")}</p>
        <p class="text-xs text-on-surface-variant">{compaction_detail(value(@snapshot, :last_compaction))}</p>
        <details :if={value(@snapshot, :last_compaction)} class="mt-1 text-xs text-on-surface-variant">
          <summary class="cursor-pointer">Last compaction details</summary>
          <dl class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-2 gap-y-1 font-mono">
            <dt>trigger</dt><dd>{display(value(value(@snapshot, :last_compaction), :trigger), "unknown")}</dd>
            <dt>source leaf</dt><dd class="break-all">{display(value(value(@snapshot, :last_compaction), :source_leaf_id), "unknown")}</dd>
            <dt>summary entry</dt><dd class="break-all">{display(value(value(@snapshot, :last_compaction), :summary_id), "unknown")}</dd>
            <dt>requests</dt><dd class="break-all">{request_ids(value(@snapshot, :last_compaction))}</dd>
            <dt>measurement</dt><dd>{measurement_sources(value(@snapshot, :last_compaction))}</dd>
          </dl>
        </details>
      </section>
      <section :if={value(@snapshot, :parent_session_id)}>
        <h2 class="text-xs font-semibold">Lineage</h2>
        <.link
          :if={value(@snapshot, :parent_path)}
          navigate={value(@snapshot, :parent_path)}
          class="break-all font-mono text-xs text-primary underline"
        >forked from: {value(@snapshot, :parent_session_id)}</.link>
        <p :if={is_nil(value(@snapshot, :parent_path))} class="break-all font-mono text-xs text-on-surface-variant">
          forked from: {value(@snapshot, :parent_session_id)}
        </p>
      </section>
    </aside>
    """
  end

  attr(:policy, :map, required: true)

  def context_budget_card(assigns) do
    ~H"""
    <section class="sigma-context-budget border border-outline-variant p-3" aria-label="Context budget">
      <h2 class="text-xs font-semibold">Context budget</h2>
      <p class="font-mono text-sm">estimate: {display(@policy[:estimate] || @policy["estimate"], "unknown")}</p>
      <p class="text-xs text-on-surface-variant">source: {display(@policy[:estimate_source] || @policy["estimate_source"], "unknown")}</p>
      <p class="font-mono text-sm">last measured: {display(@policy[:last_measured] || @policy["last_measured"], "unknown")}</p>
      <p class="text-xs text-on-surface-variant">measurement: {display(@policy[:measurement_source] || @policy["measurement_source"], "unknown")}</p>
      <p class="text-xs text-on-surface-variant">window: {display(@policy[:context_window] || @policy["context_window"], "unknown")} ({display(@policy[:window_source] || @policy["window_source"], "unknown")})</p>
      <p class="font-mono text-sm">remaining: {display(@policy[:tokens_remaining] || @policy["tokens_remaining"], "unknown")}</p>
      <p class="text-xs text-on-surface-variant">threshold: {display(@policy[:threshold] || @policy["threshold"], "unknown")}</p>
      <p class="text-xs text-on-surface-variant">check: {display(@policy[:check_phase] || @policy["check_phase"], "unknown")}</p>
      <p class={overflow_class(@policy)}>budget: {display(@policy[:overflow] || @policy["overflow"], "unknown")}</p>
      <p :if={@policy[:estimate_stale] || @policy["estimate_stale"]} class="text-warning text-xs">estimate stale</p>
    </section>
    """
  end

  attr(:branches, :list, required: true)

  def branch_alternatives(assigns) do
    original_leaf_ids =
      assigns.branches
      |> Enum.filter(&(is_binary(value(&1, :retry_of_turn_id)) and value(&1, :retry_of_turn_id) != ""))
      |> Enum.reduce(MapSet.new(), fn retry, originals ->
        original =
          Enum.find(assigns.branches, fn candidate ->
            value(candidate, :active?) != true and
              value(candidate, :branch_point_id) == value(retry, :branch_point_id)
          end)

        if original,
          do: MapSet.put(originals, value(original, :leaf_id)),
          else: originals
      end)

    assigns = assign(assigns, :original_leaf_ids, original_leaf_ids)

    ~H"""
    <section
      :if={length(@branches) > 1}
      class="sigma-branch-alternatives border-t border-outline-variant pt-3"
      aria-label="Alternative executions"
    >
      <h2 class="text-xs font-semibold text-on-surface">Alternative executions</h2>
      <p class="mt-1 text-xs text-on-surface-variant">
        Original and replacement answers remain available in the journal.
      </p>
      <ol class="mt-2 divide-y divide-outline-variant">
        <li :for={branch <- @branches} class="py-2 first:pt-0 last:pb-0">
          <div class="flex min-w-0 items-center justify-between gap-2">
            <strong class="truncate text-xs text-on-surface">
              {branch_label(branch, @original_leaf_ids)}
            </strong>
            <span class={branch_status_class(branch)}>
              {if value(branch, :active?), do: "active", else: "preserved"}
            </span>
          </div>
          <dl class="mt-1 grid grid-cols-[auto_minmax(0,1fr)] gap-x-2 text-[10px] text-on-surface-variant">
            <dt>turn</dt>
            <dd class="truncate font-mono" title={display(value(branch, :turn_id), "unknown")}>
              {display(value(branch, :turn_id), "unknown")}
            </dd>
            <dt>branch point</dt>
            <dd class="truncate font-mono" title={display(value(branch, :branch_point_id), "root")}>
              {display(value(branch, :branch_point_id), "root")}
            </dd>
            <dt :if={value(branch, :retry_of_turn_id)}>retry of</dt>
            <dd
              :if={value(branch, :retry_of_turn_id)}
              class="truncate font-mono"
              title={value(branch, :retry_of_turn_id)}
            >
              {value(branch, :retry_of_turn_id)}
            </dd>
          </dl>
          <p :if={message_text(branch, :last_user)} class="mt-1 text-xs text-on-surface-variant">
            <span class="font-semibold text-on-surface">Prompt:</span>
            {message_text(branch, :last_user)}
          </p>
          <p
            :if={message_text(branch, :last_assistant)}
            class="mt-1 max-h-40 overflow-y-auto whitespace-pre-wrap break-words text-xs text-on-surface"
          >
            <span class="font-semibold">Answer:</span>
            {message_text(branch, :last_assistant)}
          </p>
          <p
            :if={is_nil(message_text(branch, :last_assistant))}
            class="mt-1 text-xs text-on-surface-variant"
          >
            Answer unavailable or still running.
          </p>
        </li>
      </ol>
    </section>
    """
  end

  attr(:compaction, :map, required: true)

  def compaction_summary(assigns) do
    ~H"""
    <section class="sigma-compaction-summary text-xs" aria-label="Compaction summary">
      <span>successful compactions: {@compaction[:successful_compactions] || 0}</span>
      <span :if={@compaction[:last]} class="ml-2">last: {display(@compaction[:last], "unknown")}</span>
      <span :if={@compaction[:partial?]} class="ml-2 text-warning">history partial</span>
    </section>
    """
  end

  attr(:status, :atom, required: true)

  def turn_status(assigns) do
    ~H"""
    <span class={["sigma-turn-status", status_class(@status)]} role="status">{status_label(@status)}</span>
    """
  end

  attr(:disabled, :boolean, default: false)
  attr(:on_retry, :string, default: "retry")
  attr(:on_fork, :string, default: "fork")

  def action_bar(assigns) do
    ~H"""
    <div class="sigma-action-bar flex flex-wrap gap-2" role="group" aria-label="Turn actions">
      <button type="button" class="btn btn-ghost btn-xs" phx-click={@on_retry} disabled={@disabled} aria-label="Retry turn">
        <.dm_mdi name="refresh" class="h-3 w-3" /> Retry
      </button>
      <button type="button" class="btn btn-ghost btn-xs" phx-click={@on_fork} disabled={@disabled} aria-label="Fork session">
        <.dm_mdi name="source-branch" class="h-3 w-3" /> Fork
      </button>
    </div>
    """
  end

  def side_effect_warning(assigns) do
    ~H"""
    <p class="sigma-operation-warning text-xs text-warning" role="note">
      Retry, Resend, and Fork change conversation history only. They do not roll back files, commands, Git changes, or external requests; shared workspaces remain shared.
    </p>
    """
  end

  defp metric_value(map, key),
    do: display(Map.get(map, key) || Map.get(map, Atom.to_string(key)), "unknown")

  defp display(nil, fallback), do: fallback

  defp display(value, _fallback) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp display(value, _fallback), do: to_string(value)
  defp duration(nil), do: "unknown"
  defp duration(ms) when is_integer(ms) and ms >= 0, do: "#{ms}ms"
  defp duration(_), do: "unknown"
  defp throughput(%{throughput: value}), do: throughput_value(value)

  defp throughput(map) do
    aggregate = Map.get(map, :average_llm_tok_s) || Map.get(map, "average_llm_tok_s")
    output = value(map, :output_tokens_total)
    elapsed = value(map, :elapsed_ms)

    request_rate =
      if is_integer(output) and is_integer(elapsed) and elapsed > 0,
        do: output / (elapsed / 1_000)

    throughput_value(aggregate || request_rate)
  end

  defp throughput_value(nil), do: "unknown"
  defp throughput_value(value), do: "#{display(value, "unknown")} tok/s"

  defp usage_total(snapshot),
    do: metric_value(snapshot[:own_usage] || snapshot["own_usage"] || %{}, :total_tokens)

  defp usage_value(snapshot, key),
    do: metric_value(value(snapshot, :own_usage) || %{}, key)

  defp inherited_total(snapshot),
    do: metric_value(value(snapshot, :inherited_usage) || %{}, :total_tokens)

  defp inherited_requests(snapshot) do
    inherited = value(snapshot, :inherited_usage) || %{}
    Map.get(inherited, :request_count) || Map.get(inherited, "request_count") || 0
  end

  defp compaction_detail(nil), do: "last: none recorded"

  defp compaction_detail(compaction) do
    before_tokens = value(compaction, :before_tokens)
    after_tokens = value(compaction, :after_tokens)
    finished_at = value(compaction, :finished_at)

    "last: #{display(finished_at, "time unknown")} · #{display(before_tokens, "unknown")} -> #{display(after_tokens, "unknown")}"
  end

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_map, _key), do: nil

  defp provider_model(metrics) do
    case {value(metrics, :provider), value(metrics, :model)} do
      {provider, model} when is_binary(provider) and is_binary(model) -> "#{provider}/#{model}"
      _ -> "unknown"
    end
  end

  defp usage_groups(snapshot, key) do
    case value(snapshot, key) do
      groups when is_map(groups) ->
        groups
        |> Enum.map(fn {name, usage} -> {to_string(name), usage} end)
        |> Enum.sort_by(&elem(&1, 0))

      _ ->
        []
    end
  end

  defp model_groups(snapshot) do
    case value(snapshot, :usage_by_model) do
      groups when is_list(groups) -> groups
      _ -> []
    end
  end

  defp timestamp_ms(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :millisecond)
      _ -> nil
    end
  end

  defp timestamp_ms(_value), do: nil

  defp request_ids(compaction) do
    case value(compaction, :request_ids) do
      ids when is_list(ids) and ids != [] -> Enum.join(ids, ", ")
      _ -> "unknown"
    end
  end

  defp measurement_sources(compaction) do
    before_source = display(value(compaction, :before_source), "unknown")
    after_source = display(value(compaction, :after_source), "unknown")
    "#{before_source} -> #{after_source}"
  end

  defp branch_label(branch, original_leaf_ids) do
    cond do
      value(branch, :active?) -> "Active execution"
      MapSet.member?(original_leaf_ids, value(branch, :leaf_id)) -> "Original execution"
      true -> "Preserved execution"
    end
  end

  defp branch_status_class(branch) do
    if value(branch, :active?),
      do: "shrink-0 text-[10px] font-semibold text-primary",
      else: "shrink-0 text-[10px] text-on-surface-variant"
  end

  defp message_text(branch, key) do
    branch
    |> value(key)
    |> value(:text)
  end

  defp overflow_class(policy) do
    case value(policy, :overflow) do
      status when status in [:overflow, :hard_overflow] -> "text-xs text-error"
      :unknown -> "text-xs text-on-surface-variant"
      _ -> "text-xs text-on-surface-variant"
    end
  end

  defp coverage(snapshot) do
    case snapshot[:coverage] || snapshot["coverage"] do
      %{known: known, total: total} -> "coverage: #{known}/#{total}"
      %{"known" => known, "total" => total} -> "coverage: #{known}/#{total}"
      _ -> "coverage: unknown"
    end
  end

  defp status_class(status) when status in [:failed, :cancelled, :error], do: "text-error"
  defp status_class(status) when status in [:running, :waiting, :compacting], do: "text-warning"
  defp status_class(_), do: "text-on-surface-variant"
  defp status_label(nil), do: "unknown"
  defp status_label(status), do: status |> to_string() |> String.replace("_", " ")
end
