defmodule Sigma.Web.SkillsControllerTest do
  use Sigma.Web.ConnCase, async: false

  alias Sigma.Session.RepoManager

  test "reports explicit skills capabilities" do
    conn = get(build_conn(), "/api/v1/capabilities")
    response = Jason.decode!(conn.resp_body)
    assert conn.status == 200
    assert response["skills"]["localCatalog"]
    assert response["skills"]["conditionalPublication"] == false
  end

  @tag :tmp_dir
  test "lists source-aware skills for a registered repository", %{conn: conn, tmp_dir: tmp_dir} do
    previous = Application.get_env(:sigma_session, :agent_dir)
    Application.put_env(:sigma_session, :agent_dir, Path.join(tmp_dir, "agent"))

    try do
      workdir = Path.join(tmp_dir, "repo")
      File.mkdir_p!(Path.join([workdir, ".agents", "skills", "review"]))
      RepoManager.add_repo(workdir, name: "Repo")

      File.write!(
        Path.join([workdir, ".agents", "skills", "review", "SKILL.md"]),
        "---\nname: review\ndescription: Review code\n---\nBody"
      )

      repository_id = Base.url_encode64(workdir, padding: false)
      conn = get(conn, "/api/v1/skills?repositoryId=#{repository_id}")
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert Enum.any?(response["items"], &(&1["name"] == "review" and &1["description"] == "Review code"))
    after
      if previous, do: Application.put_env(:sigma_session, :agent_dir, previous), else: Application.delete_env(:sigma_session, :agent_dir)
    end
  end
end
