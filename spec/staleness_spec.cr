require "./spec_helper"
include Hace

# Single source of truth for the scenario's Hacefile. Tests rewrite it
# explicitly instead of trusting the on-disk copy, so a crashed run can
# never pollute later runs through a half-edited fixture. The trailing
# "\n" matches the committed fixture byte for byte (heredocs drop the
# final newline), so spec runs leave the working tree clean.
FIXTURE = <<-YAML + "\n"
  tasks:
    greet:
      default: true
      outputs:
        - result.txt
      dependencies:
        - input.txt
      commands: |
        cp input.txt result.txt
  YAML

# Editing a task's recipe must invalidate previously built outputs even when
# no input file changed. Recipe stamps (SHA1 of commands/shell/cwd declared
# as an extra task input) provide that; these specs exercise the behavior
# through the CLI.
def read_result : String
  File.read("result.txt").strip
end

describe "recipe staleness" do
  it "reruns a task whose commands changed, and only then" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("recipe_change", keep: ["input.txt"]) do
      File.write("Hacefile.yml", FIXTURE)
      hace = ->(args : Array(String)) {
        Process.run(HACE_BIN, args, output: output, error: error)
      }

      # First run executes the recipe.
      status = hace.call(["--quiet"])
      status.success?.should be_true
      read_result.should eq("one")

      # An identical run is a no-op: nothing is stale.
      status = hace.call(["--question"])
      status.exit_code.should eq(0)

      # Editing the commands in the Hacefile triggers a rebuild even
      # though the input file did not change...
      File.write("Hacefile.yml", FIXTURE.gsub(
        "cp input.txt result.txt",
        "sed 's/one/two/' input.txt > result.txt"
      ))
      status = hace.call(["--question"])
      status.exit_code.should eq(1)
      hace.call(["--quiet"])
      read_result.should eq("two")

      # ...and once rebuilt, the new recipe is stable too.
      status = hace.call(["--question"])
      status.exit_code.should eq(0)
    ensure
      File.write("Hacefile.yml", FIXTURE)
    end
  end

  it "reports edited recipes as stale without running them" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("recipe_change", keep: ["input.txt"]) do
      File.write("Hacefile.yml", FIXTURE)
      Process.run(HACE_BIN, ["--quiet"], output: output, error: error)

      edited = FIXTURE.gsub("cp input.txt result.txt",
        "sed 's/one/three/' input.txt > result.txt")
      File.write("Hacefile.yml", edited)
      status = Process.run(HACE_BIN, ["--question"], output: output, error: error)
      status.exit_code.should eq(1)
      read_result.should eq("one")
    ensure
      File.write("Hacefile.yml", FIXTURE)
    end
  end

  it "changes to shell also trigger a rebuild" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("recipe_change", keep: ["input.txt"]) do
      File.write("Hacefile.yml", FIXTURE)
      status = Process.run(HACE_BIN, ["--quiet"], output: output, error: error)
      status.success?.should be_true

      # Same commands, different global shell: the recipe signature changes,
      # so the task executes again even though input.txt did not change.
      # Re-execution is asserted via Croupier's own log line.
      File.write("Hacefile.yml", FIXTURE.sub("tasks:", "shell: \"/bin/bash\"\ntasks:"))
      Process.run(HACE_BIN, [] of String, output: output, error: error)
      (output.to_s + error.to_s).should contain("Started task: greet")
    ensure
      File.write("Hacefile.yml", FIXTURE)
    end
  end
end
