defmodule Hiraeth.DevEnvironmentCIContractTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)
  @workflow Path.join([@repo_root, ".github", "workflows", "ci.yml"])

  @tag :ci_devenv_contract
  test "CI hosts the gate, sidecar, visual, and accessibility lanes" do
    assert File.regular?(@workflow),
           "expected .github/workflows/ci.yml to host the verification lanes"

    workflow = File.read!(@workflow)

    assert workflow =~ "mix gate"
    assert workflow =~ "sidecar"
    assert workflow =~ "scripts/qa/design_screenshots.mjs"
    assert workflow =~ "scripts/qa/accessibility_screenshots.mjs"
    assert workflow =~ "postgres:16"
    assert workflow =~ "workflow_dispatch"
  end

  @tag :ci_devenv_contract
  test "the accessibility lane is wired to axe-core and fails on serious findings" do
    script = File.read!(Path.join([@repo_root, "scripts", "qa", "accessibility_screenshots.mjs"]))

    assert script =~ "@axe-core/playwright"
    assert script =~ ~s|violation.impact === "serious"|
    assert script =~ ~s|violation.impact === "critical"|
  end
end
