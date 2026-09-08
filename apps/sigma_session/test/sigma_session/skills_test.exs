defmodule Sigma.Session.SkillsTest do
  use ExUnit.Case, async: true

  alias Sigma.Session.Skills

  @tag :tmp_dir
  test "discovers skill metadata from SKILL.md files", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join([tmp_dir, ".agents", "skills", "repo-skill"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: repo-skill
      description: Helps with repository work
      disable-model-invocation: true
      ---
      Use this skill.
      """
    )

    assert %{skills: [skill], diagnostics: []} =
             Skills.list_dir(Path.join([tmp_dir, ".agents", "skills"]), :repository)

    assert skill.name == "repo-skill"
    assert skill.description == "Helps with repository work"
    assert skill.path == Path.join(skill_dir, "SKILL.md")
    assert skill.source == :repository
    assert skill.disable_model_invocation? == true
  end

  @tag :tmp_dir
  test "skips missing skill directories", %{tmp_dir: tmp_dir} do
    assert %{skills: [], diagnostics: []} =
             Skills.list_dir(Path.join([tmp_dir, ".agents", "skills"]), :repository)
  end

  @tag :tmp_dir
  test "reports invalid skill metadata", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join([tmp_dir, ".agents", "skills", "broken-skill"])
    File.mkdir_p!(skill_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), "---\nname: broken-skill\n---\nBody")

    assert %{skills: [], diagnostics: [diagnostic]} =
             Skills.list_dir(Path.join([tmp_dir, ".agents", "skills"]), :repository)

    assert diagnostic.path == Path.join(skill_dir, "SKILL.md")
    assert diagnostic.message == "description is required"
  end

  @tag :tmp_dir
  test "parses folded block scalars (> and >-) in skill description", %{tmp_dir: tmp_dir} do
    skills_root = Path.join([tmp_dir, ".agents", "skills"])
    agent_note_dir = Path.join(skills_root, "agent-note")
    caveman_dir = Path.join(skills_root, "caveman")
    File.mkdir_p!(agent_note_dir)
    File.mkdir_p!(caveman_dir)

    File.write!(
      Path.join(agent_note_dir, "SKILL.md"),
      """
      ---
      name: agent-note
      description: >-
        Configure Agent Note in a project's AGENTS.md when setup is requested, and recall
        or maintain project-scoped knowledge through Agent Note MCP.
      compatibility: Note workflows require Agent Note MCP.
      ---
      # Agent Note
      """
    )

    File.write!(
      Path.join(caveman_dir, "SKILL.md"),
      """
      ---
      name: caveman
      description: >
        Ultra-compressed communication mode. Cuts token usage ~75% by dropping
        filler, articles, and pleasantries while keeping full technical accuracy.
      ---
      # Caveman
      """
    )

    assert %{skills: skills, diagnostics: []} = Skills.list_dir(skills_root, :global)
    skills_by_name = Map.new(skills, &{&1.name, &1})

    assert skills_by_name["agent-note"].description ==
             "Configure Agent Note in a project's AGENTS.md when setup is requested, and recall or maintain project-scoped knowledge through Agent Note MCP."

    assert skills_by_name["caveman"].description ==
             "Ultra-compressed communication mode. Cuts token usage ~75% by dropping filler, articles, and pleasantries while keeping full technical accuracy."
  end
end
