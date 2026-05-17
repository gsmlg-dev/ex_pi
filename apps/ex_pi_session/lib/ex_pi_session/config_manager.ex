defmodule ExPiSession.ConfigManager do
  @moduledoc """
  Manages AI provider and model configurations.
  """

  @config_file "config.json"

  @default_config %{
    "active_provider_id" => "anthropic-default",
    "system_prompt" => "You are an expert coding assistant operating inside π (ExPi), an Elixir-based coding agent.\nYou help users by reading files, executing commands, editing code, and writing new files.\n\nGuidelines:\n- Be concise in your responses.\n- Show file paths clearly when working with files.\n- Use bash for file operations like ls, rg, find.\n- When editing files, ensure the code remains correct and idiomatic.\n- You have access to tools for reading files, executing bash commands, and editing/writing files.",
    "credentials" => %{
      "sample-credential" => %{
        "id" => "sample-credential",
        "name" => "Sample API Key",
        "key" => ""
      }
    },
    "providers" => %{
      "anthropic-default" => %{
        "id" => "anthropic-default",
        "name" => "Anthropic Claude",
        "api_type" => "anthropic",
        "credential_id" => "",
        "model" => "claude-3-5-sonnet-latest",
        "base_url" => "https://api.anthropic.com"
      },
      "openai-default" => %{
        "id" => "openai-default",
        "name" => "OpenAI GPT-4o",
        "api_type" => "openai",
        "credential_id" => "",
        "model" => "gpt-4o",
        "base_url" => "https://api.openai.com/v1"
      }
    }
  }

  def get_config do
    path = config_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          user_config = Jason.decode!(content)
          # Merge with defaults to ensure basic structure
          deep_merge(@default_config, user_config)

        _ ->
          @default_config
      end
    else
      @default_config
    end
  end

  def save_config(config) do
    path = config_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(config, pretty: true))
    {:ok, config}
  end

  # Credentials Management

  def add_credential(name, key) do
    id = "cred_#{System.unique_integer([:positive])}"
    config = get_config()
    credentials = Map.get(config, "credentials", %{})
    new_cred = %{"id" => id, "name" => name, "key" => key}
    
    config
    |> Map.put("credentials", Map.put(credentials, id, new_cred))
    |> save_config()
  end

  def update_credential(id, updates) do
    config = get_config()
    credentials = config["credentials"]
    cred = credentials[id] || %{"id" => id}
    new_cred = Map.merge(cred, updates)
    
    config
    |> Map.put("credentials", Map.put(credentials, id, new_cred))
    |> save_config()
  end

  def delete_credential(id) do
    config = get_config()
    credentials = Map.delete(config["credentials"], id)
    
    # Also clear credential_id from any providers using it
    providers = Enum.into(config["providers"], %{}, fn {pid, p} ->
      if p["credential_id"] == id do
        {pid, Map.put(p, "credential_id", "")}
      else
        {pid, p}
      end
    end)

    config
    |> Map.put("credentials", credentials)
    |> Map.put("providers", providers)
    |> save_config()
  end

  # Providers Management

  def add_provider(params) do
    id = "prov_#{System.unique_integer([:positive])}"
    config = get_config()
    providers = Map.get(config, "providers", %{})
    new_provider = Map.put(params, "id", id)

    config
    |> Map.put("providers", Map.put(providers, id, new_provider))
    |> save_config()
  end

  def update_provider(id, updates) do
    config = get_config()
    providers = config["providers"]
    provider = providers[id] || %{"id" => id}
    new_provider = Map.merge(provider, updates)

    config
    |> Map.put("providers", Map.put(providers, id, new_provider))
    |> save_config()
  end

  def delete_provider(id) do
    config = get_config()
    providers = Map.delete(config["providers"], id)
    
    # Reset active provider if deleted
    active_id = if config["active_provider_id"] == id, do: "", else: config["active_provider_id"]

    config
    |> Map.put("providers", providers)
    |> Map.put("active_provider_id", active_id)
    |> save_config()
  end

  def set_active_provider(id) do
    get_config()
    |> Map.put("active_provider_id", id)
    |> save_config()
  end

  def update_system_prompt(prompt) do
    get_config()
    |> Map.put("system_prompt", prompt)
    |> save_config()
  end

  def get_active_provider_config do
    config = get_config()
    provider_id = config["active_provider_id"]
    provider = config["providers"][provider_id]
    
    if provider do
      # Resolve credential
      credential = config["credentials"][provider["credential_id"]]
      Map.put(provider, "resolved_key", (credential && credential["key"]) || "")
    else
      nil
    end
  end

  defp config_path do
    root = get_priv_root()
    Path.join(root, @config_file)
  end

  defp get_priv_root do
    if Mix.env() == :dev do
      cwd = File.cwd!()
      root = if File.exists?(Path.join(cwd, "apps")), do: cwd, else: Path.expand("../..", cwd)
      Path.join(root, "apps/ex_pi_session/priv")
    else
      case :code.priv_dir(:ex_pi_session) do
        {:error, :bad_name} -> Path.expand("priv", File.cwd!())
        path -> List.to_string(path)
      end
    end
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _k, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
