require "./spec_helper"
include Hace

def pattern_from_yaml(yaml : String) : Hace::PatternRule
  Hace::PatternRule.from_yaml(yaml)
end

def validation_error(yaml : String) : String?
  pattern = pattern_from_yaml(yaml)
  pattern.validate!(0)
  nil
rescue ex
  ex.message
end

# Load a Hacefile definition, run pattern resolution against the current
# directory contents, and return the hacefile for inspection.
def resolved(hacefile_yaml : String, requested : Array(String) = [] of String) : Hace::HaceFile
  hacefile = Hace::HaceFile.from_yaml(hacefile_yaml)
  hacefile.resolve_patterns(requested)
  hacefile
end

describe Hace::PatternRule do
  describe "#match_stem" do
    it "extracts the stem from matching names" do
      pattern = pattern_from_yaml(%({"outputs": ["%.o"], "commands": "cmd"}))
      pattern.match_stem("main.o").should eq("main")
    end

    it "matches patterns with prefixes and suffixes" do
      pattern = pattern_from_yaml(%({"outputs": ["gen-%.txt"], "commands": "cmd"}))
      pattern.match_stem("gen-report.txt").should eq("report")
    end

    it "rejects non matching names" do
      pattern = pattern_from_yaml(%({"outputs": ["%.o"], "commands": "cmd"}))
      pattern.match_stem("main.c").should be_nil
      pattern.match_stem("main.obj").should be_nil
    end

    it "rejects empty stems" do
      pattern = pattern_from_yaml(%({"outputs": ["%.o"], "commands": "cmd"}))
      pattern.match_stem(".o").should be_nil
    end
  end

  describe "#dependencies_for" do
    it "substitutes the stem and keeps plain dependencies" do
      pattern = pattern_from_yaml(
        %({"outputs": ["%.o"], "dependencies": ["%.c", "common.h"], "commands": "cmd"})
      )
      pattern.dependencies_for("main").should eq(["main.c", "common.h"])
    end
  end

  describe "#validate!" do
    it "requires exactly one output" do
      message = validation_error(%({"outputs": [], "commands": "cmd"}))
      (message || "").should contain("exactly one output")
    end

    it "requires one '%' in the output" do
      message = validation_error(%({"outputs": ["nope.txt"], "commands": "cmd"}))
      (message || "").should contain("exactly one '%'")

      message = validation_error(%({"outputs": ["%-%.o"], "commands": "cmd"}))
      (message || "").should contain("exactly one '%'")
    end

    it "rejects empty commands" do
      message = validation_error(%({"outputs": ["%.o"], "commands": "   "}))
      (message || "").should contain("commands cannot be empty")
    end
  end
end

describe "pattern rule resolution" do
  it "synthesizes tasks for uncovered dependencies" do
    with_scenario("pattern_basic") do
      File.write("hello.c", "int main(void){return 0;}\n")
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}.c
        tasks:
          app:
            default: true
            dependencies:
              - hello.o
            commands: |
              cc -o app hello.o
        YAML

      task = hacefile.tasks["hello.o"]
      task.outputs.should eq(["hello.o"])
      task.dependencies.should eq(["hello.c"])
      task.commands.should eq("cc -c hello.c")
      (task.description || "").should contain("from pattern %.o")
      task.stem.should eq("hello")
    end
  end

  it "expands variables inside synthesized commands" do
    with_scenario("pattern_basic") do
      Hace::VARIABLES["FLAGS"] = "-g"
      File.write("x.c", "")
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc {{ FLAGS }} -c {{ self["stem"] }}
        tasks:
          lib:
            dependencies:
              - x.o
            commands: |
              ar rcs lib.a x.o
        YAML

      hacefile.tasks["x.o"].commands.should eq("cc -g -c x")
    end
  end

  it "prefers explicit tasks over patterns" do
    with_scenario("pattern_basic") do
      File.write("hello.c", "")
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}
        tasks:
          hello.o:
            dependencies: []
            commands: |
              special build
          app:
            default: true
            dependencies:
              - hello.o
            commands: |
              cc -o app hello.o
        YAML

      hacefile.tasks["hello.o"].commands.chomp.should eq("special build")
    end
  end

  it "leaves existing files alone when no pattern prereqs exist" do
    with_scenario("pattern_basic") do
      File.write("artifact.o", "")
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}
        tasks:
          app:
            default: true
            dependencies:
              - artifact.o
            commands: |
              link artifact.o
        YAML

      hacefile.tasks.has_key?("artifact.o").should be_false
    end
  end

  it "chains patterns transitively" do
    with_scenario("pattern_basic") do
      File.write("message.tpl", "hello\n")
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.c"]
            dependencies: ["%.tpl"]
            commands: |
              cp {{ self["dependencies"][0] }} {{ self["outputs"][0] }}
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}
        tasks:
          app:
            default: true
            dependencies:
              - message.o
            commands: |
              link message.o
        YAML

      hacefile.tasks.has_key?("message.c").should be_true
      hacefile.tasks["message.o"].dependencies.should eq(["message.c"])
      hacefile.tasks["message.c"].dependencies.should eq(["message.tpl"])
    end
  end

  it "terminates on self referential patterns" do
    with_scenario("pattern_basic") do
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.x"]
            dependencies: ["%.x.z"]
            commands: |
              make {{ self["outputs"][0] }}
        tasks:
          app:
            default: true
            dependencies:
              - thing.x
            commands: |
              use thing.x
        YAML

      hacefile.tasks.has_key?("thing.x").should be_false
    end
  end

  it "instantiates tasks for CLI requested targets" do
    with_scenario("pattern_basic") do
      File.write("solo.c", "")
      hacefile_yaml = <<-'YAML'
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}
        tasks:
          app:
            default: true
            commands: |
              nothing
        YAML
      hacefile = resolved(hacefile_yaml, requested: ["solo.o"])

      hacefile.tasks.has_key?("solo.o").should be_true
    end
  end

  it "does not instantiate when prerequisites are missing entirely" do
    with_scenario("pattern_basic") do
      hacefile = resolved(<<-'YAML')
        patterns:
          - outputs: ["%.o"]
            dependencies: ["%.c"]
            commands: |
              cc -c {{ self["stem"] }}
        tasks:
          app:
            default: true
            dependencies:
              - ghost.o
            commands: |
              link ghost.o
        YAML

      hacefile.tasks.has_key?("ghost.o").should be_false
    end
  end
end

describe "pattern rules through the CLI" do
  it "builds real files using synthesized tasks" do
    output = IO::Memory.new
    error = IO::Memory.new
    success = false
    with_scenario("pattern_basic", keep: ["hello.c"]) do
      # Rewrite explicitly: earlier specs leave an empty hello.c behind and
      # this scenario keeps it.
      File.write("hello.c", "int main(void){return 0;}\n")
      status = Process.run(HACE_BIN, ["--quiet"], output: output, error: error)
      success = status.success?
      unless success
        puts output.to_s
        puts error.to_s
      end
      system("./app").should be_true
      # Content-based staleness: changing the source flips --question to 1.
      File.write("hello.c", "int main(void){return 1;}\n")
      stale_status = Process.run(HACE_BIN, ["--question"], output: output, error: error)
      stale_status.exit_code.should eq(1)
    end
    success.should be_true
  end

  it "lists synthesized instances" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("pattern_basic", keep: ["hello.c"]) do
      File.write("hello.c", "")
      Process.run(HACE_BIN, ["--list"], output: output, error: error)
    end
    result = output.to_s + error.to_s
    result.should contain("generated for hello.o")
  end
end
