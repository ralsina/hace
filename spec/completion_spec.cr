require "./spec_helper"

include Hace

describe "Shell Completion" do
  describe "generate" do
    it "should generate bash completion script" do
      script = Hace::Completion.generate("bash")
      script.should contain("_hace_completion")
      script.should contain("complete -F _hace_completion hace")
    end

    it "should generate fish completion script" do
      script = Hace::Completion.generate("fish")
      script.should contain("complete -c hace")
      script.should contain("__hace_task_names")
    end

    it "should generate zsh completion script" do
      script = Hace::Completion.generate("zsh")
      script.should contain("#compdef hace")
      script.should contain("_hace()")
    end

    it "should handle invalid shell names" do
      io = IO::Memory.new
      hace_path = File.join(__DIR__, "..", "bin", "hace")
      Process.run(hace_path, ["--completion", "invalid"],
        output: io,
        error: io)
      io.to_s.should contain("Unsupported shell")
    end
  end

  describe "get_task_names" do
    it "should return empty array for invalid Hacefile" do
      tasks = Hace::Completion.get_task_names("/nonexistent/file.yml")
      tasks.should eq([] of String)
    end

    it "should return task names from the main project Hacefile" do
      tasks = Hace::Completion.get_task_names("Hacefile.yml")
      tasks.should be_a(Array(String))
      tasks.size.should be > 0
      tasks.should contain("build")
      tasks.should contain("test")
    end
  end
end
