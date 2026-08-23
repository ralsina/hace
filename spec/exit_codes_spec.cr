require "./spec_helper"
include Hace

describe "Exit Codes" do
  it "exits 0 for --version" do
    process = Process.run(HACE_BIN, ["--version"])
    process.success?.should be_true
  end

  it "exits 0 for --help" do
    process = Process.run(HACE_BIN, ["--help"])
    process.success?.should be_true
  end

  it "exits non-zero for unknown tasks" do
    with_scenario("basic") do
      output = IO::Memory.new
      error = IO::Memory.new
      process = Process.run(HACE_BIN, ["sarasa"], output: output, error: error)
      process.success?.should be_false
      (output.to_s + error.to_s).should contain "Unknown task(s): sarasa"
    end
  end

  it "exits non-zero for malformed options" do
    output = IO::Memory.new
    error = IO::Memory.new
    process = Process.run(HACE_BIN, ["--verbosity"], output: output, error: error)
    process.success?.should be_false
    (output.to_s + error.to_s).should contain "Usage:"
  end

  it "exits non-zero when a command fails" do
    with_scenario("failure") do
      process = Process.run(HACE_BIN, [] of String)
      process.success?.should be_false
    end
  end

  it "exits 1 in question mode when tasks are stale" do
    with_scenario("no-deps") do
      process = Process.run(HACE_BIN, ["--question"])
      process.exit_code.should eq 1
    end
  end
end
