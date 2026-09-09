defmodule Sigma.Session.SlashCommandsTest do
  use ExUnit.Case, async: true

  alias Sigma.Session.SlashCommands

  test "leaves regular prompts unchanged" do
    assert SlashCommands.expand("hello") == :not_command
  end

  test "expands init into an AGENTS.md instruction prompt" do
    assert {:ok, prompt} = SlashCommands.expand("/init")

    assert prompt =~ "Set up a minimal AGENTS.md"
    assert prompt =~ "Project AGENTS.md gives Sigma Agent persistent, team-shared instructions"
    assert prompt =~ "`~/.pi/agent/AGENTS.md`"
    assert prompt =~ "Create project skills at `.agents/skills/<skill-name>/SKILL.md`"
    refute prompt =~ "CLAUDE.md"
    refute prompt =~ "Claude Code"
    refute prompt =~ ".claude/skills"
  end

  test "preserves init command arguments" do
    assert {:ok, prompt} = SlashCommands.expand("/init update")

    assert prompt =~ "Command arguments: update"
  end

  test "rejects unknown slash commands" do
    assert SlashCommands.expand("/compact") == {:error, "Unknown slash command: /compact"}
  end

  @tag :tmp_dir
  test "invokes a local skill and expands arguments once", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join([tmp_dir, ".agents", "skills", "example"])
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: example\ndescription: Example skill\n---\nDo $ARGUMENTS once."
    )

    assert {:ok, "Do inspect this once."} =
             SlashCommands.expand("/skill example inspect this", cwd: tmp_dir)

    assert {:ok, "Do inspect this once."} =
             SlashCommands.expand("/example inspect this", cwd: tmp_dir)
  end
end
