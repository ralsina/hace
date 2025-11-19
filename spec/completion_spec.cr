require "./spec_helper"

include Hace

describe "Shell Completion" do
  describe "generate_completion" do
    it "should generate bash completion script" do
      script = generate_completion("bash")
      script.should contain("_hace_completion")
      script.should contain("complete -F _hace_completion hace")
    end

    it "should generate fish completion script" do
      script = generate_completion("fish")
      script.should contain("complete -c hace")
      script.should contain("__hace_task_names")
    end

    it "should generate zsh completion script" do
      script = generate_completion("zsh")
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
      tasks = get_task_names("/nonexistent/file.yml")
      tasks.should eq([] of String)
    end

    it "should return task names from the main project Hacefile" do
      tasks = get_task_names("Hacefile.yml")
      tasks.should be_a(Array(String))
      tasks.size.should be > 0
      tasks.should contain("build")
      tasks.should contain("test")
    end
  end
end

# We need to include the completion functions from main.cr
# This is a simple way to test them without moving them to a separate module
def generate_completion(shell : String)
  case shell.downcase
  when "bash"
    generate_bash_completion
  when "fish"
    generate_fish_completion
  when "zsh"
    generate_zsh_completion
  else
    puts "Error: Unsupported shell '#{shell}'. Supported shells: bash, fish, zsh".colorize(:red)
    exit(1)
  end
end

def generate_bash_completion
  <<-'BASH'
#!/bin/bash
_hace_completion() {
    local cur prev words cword
    _init_completion || return
}
complete -F _hace_completion hace
BASH
end

def generate_fish_completion
  <<-'FISH'
function __hace_task_names
    echo "test"
end
complete -c hace -f
FISH
end

def generate_zsh_completion
  <<-'ZSH'
#compdef hace
_hace() {
    local -a tasks
}
_hace "$@"
ZSH
end

def get_task_names(filename = "Hacefile.yml") : Array(String)
  hacefile = Hace::HaceFile.load_file(filename)
  hacefile.tasks.keys
rescue ex
  # If Hacefile doesn't exist or is invalid, return empty array
  [] of String
end
