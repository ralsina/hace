require "./spec_helper"
include Hace

describe "env namespace" do
  it "exposes the merged environment view to {{ env.NAME }}" do
    logs = IO::Memory.new
    old_foo = ENV["FOO"]?
    old_mark = ENV["MARK"]?
    ENV["FOO"] = "from-process"
    ENV["MARK"] = "mark"
    begin
      with_scenario("env-namespace", logs: logs) do
        f = HaceFile.load_file("Hacefile.yml")

        # env: values are templates rendered against the pre-merge view
        f.env["PPRE"].should eq "pre:mark"

        # The namespace reflects the final merged view, not the process env
        namespace = VARIABLES["env"].as(Hash(String, Hace::Value))
        namespace["FOO"].should eq "from-file"
        ENVIRONMENT["FOO"].should eq "from-file"

        # Task fields expanded at load time against the final view
        f.tasks["show"].commands.should contain %(echo "env.FOO=from-file" > out.txt)
        # Brace-less $FOO in outputs stays literal
        f.tasks["lit"].outputs.should eq ["$FOO.txt"]
        # {{ env.NAME }} in outputs expands
        f.tasks["gen"].outputs.should eq ["from-file.txt"]

        HaceFile.run(arguments: ["show"])
        content = File.read("out.txt")
        content.should contain "env.FOO=from-file"
        # The child shell sees the same merged view (precedence fix)
        content.should contain "shell=from-file"
        # Variable indirection resolves against the merged view too
        content.should contain "var=from-file"
        # Undefined names render as empty strings
        content.should contain "missing=[]"
        content.should contain "defaulted=[dflt]"
        # Pre-merge rendering of env: values
        content.should contain "ppre=pre:mark"
        # Deprecated ${FOO} expands from the merged view (was process env)
        content.should contain "braced=from-file"
        # Brace-less $FOO stays literal at hace level (the shell expands it
        # afterwards, since the child sees the merged environment too)
        VARIABLES["braceless_var"].should eq "$FOO"
        content.should contain "braceless=[from-file]"

        HaceFile.run(arguments: ["gen"])
        File.exists?("from-file.txt").should be_true
      end

      # Exactly one deprecation warning for ${FOO} (rate limited) and one
      # brace-less warning for $FOO in variables/outputs, despite $FOO also
      # appearing in commands (where it is shell syntax and never warns)
      logs.to_s.scan("is deprecated").size.should eq 1
      logs.to_s.scan("Brace-less").size.should eq 1
    ensure
      if old_foo
        ENV["FOO"] = old_foo
      else
        ENV.delete("FOO")
      end
      if old_mark
        ENV["MARK"] = old_mark
      else
        ENV.delete("MARK")
      end
    end
  end

  it "reserves the 'env' variable name" do
    logs = IO::Memory.new
    old_a = ENV["A"]?
    ENV.delete("A")
    begin
      with_scenario("env-reserved", logs: logs) do
        HaceFile.load_file("Hacefile.yml")

        # The namespace wins over the user-defined 'env' variable
        namespace = VARIABLES["env"].as(Hash(String, Hace::Value))
        namespace["A"]?.should be_nil

        HaceFile.run(arguments: ["show"])
        File.read("out.txt").should contain "[]"

        # A CLI override named 'env' is also rejected
        HaceFile.load_file("Hacefile.yml", {"env" => "x"})
        namespace = VARIABLES["env"].as(Hash(String, Hace::Value))
        namespace.should_not eq({"A" => "x"})
      end
      logs.to_s.scan("is reserved").size.should eq 2
    ensure
      if old_a
        ENV["A"] = old_a
      else
        ENV.delete("A")
      end
    end
  end

  it "does not warn about shell variables in commands" do
    logs = IO::Memory.new
    old_my_var = ENV["MY_VAR"]?
    ENV.delete("MY_VAR")
    begin
      with_scenario("shell_execution", logs: logs) do
        HaceFile.load_file("Hacefile.yml")
        # $MY_VAR is set and used inside the task's shell: hace must not
        # expand or warn about it
        logs.to_s.should_not contain "Brace-less"
        logs.to_s.should_not contain "is deprecated"
      end
    ensure
      if old_my_var
        ENV["MY_VAR"] = old_my_var
      else
        ENV.delete("MY_VAR")
      end
    end
  end
end

describe "deprecated ${NAME} expansion" do
  it "warns from the dotenv testcase but keeps behavior" do
    output = IO::Memory.new
    error = IO::Memory.new
    hace_binary = File.join([ENV["PROJECT_ROOT"]? || Dir.current, "bin", "hace"])
    with_scenario("dotenv_test", extra_keep: [".env"]) do
      Process.run(
        hace_binary,
        ["test-env"],
        output: output,
        error: error
      )
    end

    result = output.to_s + error.to_s
    result.should contain("APP_NAME: HaceTest")
    result.should contain("expansion is deprecated")
  end
end
