require "./spec_helper"
include Hace

describe "task-to-task dependencies" do
  it "runs the dependency task before the dependent task" do
    with_scenario("task-dep") do
      File.delete?("deploy.log")
      status = Process.run(HACE_BIN, ["deploy"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      status.success?.should be_true, "hace deploy failed"
      File.read("out.txt").strip.should eq "built"
      File.exists?("deploy.log").should be_true
    end
  end

  it "re-runs the phony task while skipping the fresh file task" do
    with_scenario("task-dep", keep: [".croupier"]) do
      Process.run(HACE_BIN, ["deploy"]).success?.should be_true
      first_log = File.read("deploy.log")

      # Second run: out.txt is up to date, deploy is re-run as an aggregator.
      second = Process.run(HACE_BIN, ["deploy"], error: Process::Redirect::Pipe)
      second.success?.should be_true
      File.read("deploy.log").should eq first_log
    end
  end
end
