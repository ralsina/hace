require "./spec_helper"
include Hace

HACE_BIN = File.join(__DIR__, "..", "bin", "hace")

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

describe "Shell Execution Enhancements" do
  describe "environment variable persistence" do
    it "should persist environment variables across commands in the same task" do
      with_scenario("shell_execution") do
        result = `#{HACE_BIN} test-env-persistence`
        result.should contain("Variable: hello_world")
        result.should contain("Again: hello_world")
        $?.success?.should be_true
      end
    end
  end

  describe "fail-fast behavior" do
    it "should stop execution on first failed command" do
      with_scenario("shell_execution") do
        result = `#{HACE_BIN} test-fail-fast 2>&1`
        # Check that the command executed successfully before failing
        result.should contain("Before error")
        # Check that the command failed (exit status non-zero)
        $?.success?.should be_false
        # Check that it failed on the exit command
        result.should contain("Command failed: exit 1")
      end
    end
  end

  describe "shell configuration" do
    it "should use task-specific shell when specified" do
      with_scenario("shell_execution") do
        result = `#{HACE_BIN} test-shell-config`
        result.should contain("Shell: sh")
        $?.success?.should be_true
      end
    end
  end

  describe "backward compatibility" do
    it "should work with existing .env functionality" do
      with_scenario("dotenv_test") do
        result = `#{HACE_BIN} test-env`
        result.should contain("APP_NAME: HaceTest")
        $?.success?.should be_true
      end
    end
  end
end
