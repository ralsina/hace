require "./spec_helper"
include Hace

def with_scenario(name, keep = [] of String, logs : IO::Memory = IO::Memory.new, &)
  Log.setup(:debug, Log::IOBackend.new(io: logs, formatter: Log::ShortFormat))
  Dir.cd("spec/testcases/#{name}") do
    File.delete?(".croupier") unless keep.includes? ".croupier"
    Dir.glob("*").each do |f|
      next if f == "Hacefile.yml" || keep.includes?(f)
      if File.directory?(f)
        FileUtils.rm_rf(f)
      else
        File.delete?(f)
      end
    end
    TaskManager.cleanup
    yield
  end
end

describe "Dry Run Functionality" do
  describe "enhanced dry-run output" do
    it "should display task details with commands" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_basic") do
        Process.run(
          hace_binary,
          ["--dry-run", "simple_task"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("🔍 Task: simple_task")
      result.should contain("Commands to execute:")
      result.should contain("echo \"Hello World\"")
      result.should contain("Phony: yes")
    end

    it "should show variables expanded in commands" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_vars") do
        Process.run(
          hace_binary,
          ["--dry-run", "build"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("Building version 1.2.3")
      result.should contain("app-1.2.3")
      result.should contain("Outputs: app-1.2.3")
    end

    it "should display dependencies and outputs" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_enhanced") do
        Process.run(
          hace_binary,
          ["--dry-run", "build"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("Dependencies: test")
      result.should contain("Outputs: none")
      result.should contain("Phony: yes")
    end

    it "should handle tasks with file outputs" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_output") do
        Process.run(
          hace_binary,
          ["--dry-run", "output_task"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("Outputs: test.txt")
      result.should contain("Phony: no")
      result.should contain("echo \"Hello World\" > test.txt")
    end

    it "should show parallel execution flag" do
      output = IO::Memory.new
      error = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_parallel") do
        Process.run(
          hace_binary,
          ["--dry-run", "--parallel", "task1"],
          output: output,
          error: error
        )
      end

      combined = output.to_s + error.to_s
      combined.should contain("Running tasks with parallel=true")
    end

    it "should work with custom working directory" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_cwd") do
        Process.run(
          hace_binary,
          ["--dry-run", "cwd_task"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("Working Directory: /tmp")
    end

    it "should handle always_run flag" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_always") do
        Process.run(
          hace_binary,
          ["--dry-run", "always_task"],
          output: output
        )
      end

      result = output.to_s
      result.should contain("Always Run: yes")
    end
  end

  describe "dry-run with question mode" do
    it "should not conflict with question mode" do
      output = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dryrun_basic") do
        Process.run(
          hace_binary,
          ["--question"],
          output: output
        )
      end

      result = output.to_s
      # Question mode should not show task details
      result.should_not contain("🔍 Task:")
      result.should_not contain("Commands to execute:")
    end
  end
end
