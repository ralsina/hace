require "./spec_helper"
include Hace

# Croupier 0.14.2 fixed directory *outputs*: a no_save task producing a
# directory now hashes it with the same Merkle digest used for directory
# inputs. Previously, hash_file() read the directory as a plain file and
# raised "read (<dir>): Is a directory", so a task chaining off a generated
# directory never ran. These specs exercise that fix end-to-end through the
# CLI, in the style of task_dep_spec.cr / staleness_spec.cr.
describe "directory outputs" do
  it "runs a task that consumes a directory produced by an upstream task" do
    with_scenario("directory-output", keep: ["content.txt"]) do
      status = Process.run(HACE_BIN, ["use-dir"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      status.success?.should be_true, "hace use-dir failed"
      File.exists?("blog/post.md").should be_true
      File.read("out.md").strip.should eq "first run"
    end
  end

  it "leaves the chain fresh on a second, unchanged run" do
    with_scenario("directory-output", keep: [".croupier", "content.txt"]) do
      Process.run(HACE_BIN, ["use-dir"]).success?.should be_true
      first = File.read("out.md").strip

      # Nothing changed: the directory digest recorded at the end of the
      # first run matches the scan of the consumer's directory input, so
      # question mode reports no stale tasks.
      status = Process.run(HACE_BIN, ["--question", "use-dir"])
      status.exit_code.should eq 0
      File.read("out.md").strip.should eq first
    end
  end

  it "re-runs the consumer when a file inside the produced directory changes" do
    with_scenario("directory-output", keep: [".croupier", "content.txt"]) do
      Process.run(HACE_BIN, ["use-dir"]).success?.should be_true
      File.read("out.md").strip.should eq "first run"

      # Editing the directory contents re-stales only the consumer; the
      # producer (whose sole input content.txt is unchanged, and whose
      # digest already recorded the old directory) stays fresh.
      File.write("blog/post.md", "edited\n")
      status = Process.run(HACE_BIN, ["--question", "use-dir"])
      status.exit_code.should eq 1

      Process.run(HACE_BIN, ["use-dir"]).success?.should be_true
      File.read("out.md").strip.should eq "edited"
    end
  end
end
