require "./spec_helper"
include Hace

def with_scenario(name, keep = [] of String, logs : IO::Memory = IO::Memory.new, &)
  Log.setup(:debug, Log::IOBackend.new(io: logs, formatter: Log::ShortFormat))
  Dir.cd("spec/testcases/#{name}") do
    File.delete?(".croupier") unless keep.includes? ".croupier"
    Dir.glob("*").each do |f|
      next if f == "Hacefile.yml" || f == ".env" || keep.includes?(f)
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

describe "Dotenv Support" do
  describe "automatic .env loading" do
    it "should load environment variables from .env file" do
      output = IO::Memory.new
      error = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
      with_scenario("dotenv_test") do
        Process.run(
          hace_binary,
          ["test-env"],
          output: output,
          error: error
        )
      end

      result = output.to_s + error.to_s
      result.should contain("Loading environment from:")
      result.should contain("APP_NAME: HaceTest")
      result.should contain("VERSION: 1.2.3")
      result.should contain("DEBUG: true")
    end

    it "should not fail when .env file doesn't exist" do
      output = IO::Memory.new
      error = IO::Memory.new
      hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])

      # Create test without .env file
      Dir.mkdir_p("/tmp/hace_test_no_env")
      File.write("/tmp/hace_test_no_env/Hacefile.yml", "tasks:\n  test:\n    phony: true\n    commands: echo 'test'")

      Process.run(
        hace_binary,
        ["-f", "/tmp/hace_test_no_env/Hacefile.yml", "test"],
        output: output,
        error: error
      )

      result = output.to_s + error.to_s
      result.should contain("test")
      result.should_not contain("Loading environment from: .env")

      # Cleanup
      FileUtils.rm_rf("/tmp/hace_test_no_env")
    end
  end
end
