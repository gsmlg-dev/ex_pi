defmodule Sigma.Web.SkillsController do
  use Sigma.Web, :controller

  alias Sigma.Agent.SkillInvocationService
  alias Sigma.Session.{ConfigManager, RepoManager, Skills, SkillInvocationStore, SlashCommands}

  def capabilities(conn, _params) do
    json(conn, %{
      "skills" => %{
        "localCatalog" => true,
        "manualInvocation" => true,
        "modelActivation" => true,
        "remoteRead" => true,
        "conditionalPublication" => false
      },
    })
  end

  def index(conn, params) do
    with {:ok, workdir} <- repository_workdir(params["repositoryId"]),
         catalog <- Skills.Catalog.build(workdir) do
      items =
        catalog.skills
        |> Enum.filter(& &1.enabled?)
        |> Enum.map(&descriptor/1)

      json(conn, %{
        "catalogRevision" => catalog.revision,
        "items" => items,
        "nextCursor" => nil,
        "partial" => false,
        "diagnostics" => Enum.map(catalog.diagnostics, &diagnostic/1)
      })
    else
      {:error, :invalid_repository} -> json(conn |> put_status(:bad_request), %{error: "invalid repositoryId"})
    end
  end

  def show(conn, %{"id" => skill_id} = params) do
    with {:ok, workdir} <- repository_workdir(params["repositoryId"]),
         catalog <- Skills.Catalog.build(workdir),
         skill when is_map(skill) <- Enum.find(catalog.skills, &(&1.skill_id == skill_id)) do
      json(conn, %{"catalogRevision" => catalog.revision, "item" => descriptor(skill)})
    else
      nil -> json(conn |> put_status(:not_found), %{error: "skill_not_found"})
      {:error, :invalid_repository} -> json(conn |> put_status(:bad_request), %{error: "invalid repositoryId"})
    end
  end

  def create_invocation(conn, %{"session_id" => session_id} = params) do
    request_key = List.first(get_req_header(conn, "idempotency-key"))
    repository_id = params["repositoryId"]

    with true <- is_binary(request_key) and request_key != "",
         {:ok, workdir} <- repository_workdir(repository_id),
         sessions_dir <- ConfigManager.ensure_sessions_dir(workdir),
         {:ok, event} <-
           SkillInvocationService.invoke(
             Map.merge(params, %{"sessionId" => session_id, "requestKey" => request_key}),
             invocation_context(workdir, sessions_dir)
           ) do
      json(conn |> put_status(:accepted), event.payload)
    else
      false -> json(conn |> put_status(:bad_request), %{error: "idempotency_key_required"})
      {:error, :invalid_repository} -> json(conn |> put_status(:bad_request), %{error: "invalid repositoryId"})
      {:error, :idempotency_conflict} -> json(conn |> put_status(:conflict), %{error: "idempotency_conflict"})
      {:error, reason} -> json(conn |> put_status(:unprocessable_entity), %{error: to_string(reason)})
    end
  end

  def show_invocation(conn, %{"session_id" => session_id, "invocation_id" => invocation_id} = params) do
    with {:ok, workdir} <- repository_workdir(params["repositoryId"]),
         sessions_dir <- ConfigManager.ensure_sessions_dir(workdir),
         {:ok, records} <- SkillInvocationStore.list(sessions_dir, session_id),
         record when is_map(record) <- Enum.find(records, &(&1["invocationId"] == invocation_id)) do
      json(conn, record)
    else
      nil -> json(conn |> put_status(:not_found), %{error: "invocation_not_found"})
      {:error, :invalid_repository} -> json(conn |> put_status(:bad_request), %{error: "invalid repositoryId"})
      {:error, reason} -> json(conn |> put_status(:internal_server_error), %{error: to_string(reason)})
    end
  end

  defp invocation_context(workdir, sessions_dir) do
    %{
      repo_path: workdir,
      sessions_dir: sessions_dir,
      skill_invocation_store: %{
        find: fn session_id, request_key -> SkillInvocationStore.find(sessions_dir, session_id, request_key) end,
        list: fn session_id -> SkillInvocationStore.list(sessions_dir, session_id) end,
        reserve: fn session_id, record -> SkillInvocationStore.reserve(sessions_dir, session_id, record) end,
        update: fn session_id, invocation_id, changes -> SkillInvocationStore.update(sessions_dir, session_id, invocation_id, changes) end
      },
      skill_expander: &SlashCommands.expand/2
    }
  end

  defp repository_workdir(encoded) when is_binary(encoded) do
    with {:ok, workdir} <- Base.url_decode64(encoded, padding: false),
         %{} = repo <- RepoManager.get_repo(workdir) do
      {:ok, Path.expand(repo["path"])}
    else
      _ -> {:error, :invalid_repository}
    end
  end

  defp repository_workdir(_encoded), do: {:error, :invalid_repository}

  defp descriptor(skill) do
    %{
      "skillId" => skill.skill_id,
      "sourceId" => skill.source_id,
      "sourceKey" => skill.source_key,
      "name" => skill.name,
      "description" => skill.description,
      "manualOnly" => skill.disable_model_invocation?,
      "argumentHint" => skill.argument_hint,
      "enabled" => skill.enabled?
    }
  end

  defp diagnostic(diagnostic), do: %{"path" => diagnostic.path, "message" => diagnostic.message}
end
