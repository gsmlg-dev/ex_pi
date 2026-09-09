tmp = Path.join(System.tmp_dir!(), "sigma-skills-smoke-#{System.unique_integer([:positive])}")
skill_dir = Path.join([tmp, ".agents", "skills", "smoke"])
File.mkdir_p!(skill_dir)

try do
  File.write!(
    Path.join(skill_dir, "SKILL.md"),
    "---\nname: smoke\ndescription: Local smoke skill\n---\nUse $ARGUMENTS."
  )

  catalog = Sigma.Session.Skills.Catalog.build(tmp)
  {:ok, skill} = Sigma.Session.Skills.Catalog.resolve(catalog, "smoke")
  {:ok, snapshot} = Sigma.Session.Skills.Snapshot.prepare(skill)
  {:ok, expanded} = Sigma.Session.SlashCommands.expand("/skill smoke verify", cwd: tmp)

  {:ok, result} =
    Sigma.Tools.ActivateSkill.execute("smoke", %{"reference" => "smoke", "arguments" => "verify"},
      cwd: tmp
    )

  true = snapshot.digest.scheme == "sha256-tree-v1"
  true = expanded == "Use verify."
  [%{text: "Use verify."}] = result.content

  record = %{
    "invocationId" => "smoke-invocation",
    "requestKey" => "smoke-key",
    "fingerprint" => "smoke-fingerprint",
    "state" => "running"
  }

  {:ok, _} = Sigma.Session.SkillInvocationStore.reserve(tmp, "session-smoke", record)
  {:ok, [_interrupted]} = Sigma.Session.SkillInvocationStore.recover(tmp, "session-smoke")

  IO.puts("skills local smoke: passed")
after
  File.rm_rf!(tmp)
end
