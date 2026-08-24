require "./spec_helper"
include Hace

# Convert Makefile *content* and parse the result back as a HaceFile,
# which is exactly what the runtime integration does.
def convert_to_hacefile(makefile_content : String) : Hace::HaceFile
  yaml = MakefileConverter.convert(makefile_content)
  Hace::HaceFile.from_yaml(yaml)
end

describe Hace::MakefileConverter do
  describe ".looks_like_makefile?" do
    it "recognizes conventional Makefile names" do
      MakefileConverter.looks_like_makefile?("Makefile").should be_true
      MakefileConverter.looks_like_makefile?("dir/makefile").should be_true
      MakefileConverter.looks_like_makefile?("GNUmakefile").should be_true
    end

    it "rejects other filenames" do
      MakefileConverter.looks_like_makefile?("Hacefile.yml").should be_false
      MakefileConverter.looks_like_makefile?("Makefile.old").should be_false
      MakefileConverter.looks_like_makefile?("makefileish").should be_false
    end
  end

  describe "#convert" do
    it "converts a basic rule" do
      hacefile = convert_to_hacefile(<<-MAKE)
        hello:
        	gcc -o hello hello.c
        MAKE

      task = hacefile.tasks["hello"]
      task.commands.should contain("gcc -o hello hello.c")
      task.dependencies.should be_empty
    end

    it "keeps prerequisites as dependencies" do
      hacefile = convert_to_hacefile(<<-MAKE)
        app: main.o util.o
        	ld -o app main.o util.o
        MAKE

      hacefile.tasks["app"].dependencies.should eq(["main.o", "util.o"])
    end

    it "marks the first rule as default" do
      hacefile = convert_to_hacefile(<<-MAKE)
        all: app

        app:
        	touch app
        MAKE

      hacefile.tasks["all"].default?.should be_true
      hacefile.tasks["app"].default?.should be_false
    end

    it "honors .DEFAULT_GOAL" do
      hacefile = convert_to_hacefile(<<-MAKE)
        all: app

        app:
        	touch app

        .DEFAULT_GOAL := app
        MAKE

      hacefile.tasks["app"].default?.should be_true
      hacefile.tasks["all"].default?.should be_false
    end

    it "marks .PHONY targets" do
      hacefile = convert_to_hacefile(<<-MAKE)
        build:
        	touch build

        clean:
        	rm -f build

        .PHONY: clean
        MAKE

      hacefile.tasks["build"].phony?.should be_false
      hacefile.tasks["clean"].phony?.should be_true
    end

    it "turns rules without a recipe into phony aggregator tasks" do
      hacefile = convert_to_hacefile(<<-MAKE)
        all: app docs

        app:
        	touch app

        docs:
        	touch docs
        MAKE

      hacefile.tasks["all"].phony?.should be_true
    end

    it "converts plain, conditional and appending assignments" do
      hacefile = convert_to_hacefile(<<-MAKE)
        NAME = world
        LAZY ?= fallback
        FLAGS += -O2
        MAKE

      hacefile.variables["NAME"].should eq("world")
      hacefile.variables["LAZY"].should eq("fallback")
      hacefile.variables["FLAGS"].should eq("-O2")
    end

    it "lets later plain assignments override earlier ones" do
      hacefile = convert_to_hacefile("LAZY ?= fallback\nLAZY = final\n")
      hacefile.variables["LAZY"].should eq("final")
    end

    it "expands chained variable references" do
      hacefile = convert_to_hacefile(<<-MAKE)
        CC = gcc
        COMPILE = $(CC) -c
        MAKE

      hacefile.variables["COMPILE"].should eq("gcc -c")
    end

    it "expands undefined variables to nothing, like make does" do
      hacefile = convert_to_hacefile("X = a$(UNDEFINED_THING)b\n")
      hacefile.variables["X"].should eq("ab")
    end

    it "maps export assignments to environment entries" do
      hacefile = convert_to_hacefile("export BUILD_MODE = fast\n")
      hacefile.env["BUILD_MODE"].should eq("fast")
    end

    it "makes exported variables available to recipes" do
      hacefile = convert_to_hacefile(<<-MAKE)
        export GREETING = hi
        all:
        \techo $(GREETING) $GREETING
        MAKE

      hacefile.env["GREETING"].should eq("hi")
      hacefile.variables["GREETING"].should eq("hi")
      hacefile.tasks["all"].commands.should contain("{{ GREETING }}")
    end

    it "maps the SHELL variable to the Hacefile shell setting" do
      hacefile = convert_to_hacefile("SHELL = /bin/bash\n")
      hacefile.shell.should eq("/bin/bash")
      hacefile.variables.has_key?("SHELL").should be_false
    end

    it "translates variable references in recipes to Jinja syntax" do
      hacefile = convert_to_hacefile(<<-MAKE)
        CC = gcc
        build:
        	$(CC) -v
        MAKE

      hacefile.tasks["build"].commands.should contain("{{ CC }}")
    end

    it "translates automatic variables to self references" do
      yaml = MakefileConverter.convert(<<-MAKE)
        out: dep1 dep2
        	cmd $@ $^
        	other $<
        MAKE

      yaml.should contain(%({{ self["outputs"][0] }}))
      yaml.should contain(%({{ self["dependencies"] | join(" ") }}))
      yaml.should contain(%({{ self["dependencies"][0] }}))
    end

    it "unescapes $$ into a literal dollar sign" do
      hacefile = convert_to_hacefile("price:\n\techo $$HOME\n")
      hacefile.tasks["price"].commands.should eq("echo $HOME")
    end

    it "supports multiple targets per rule as outputs" do
      hacefile = convert_to_hacefile(<<-MAKE)
        one two:
        	touch one two
        MAKE

      hacefile.tasks["one"].outputs.should eq(["one", "two"])
    end

    it "merges duplicated rules keeping the last recipe" do
      hacefile = convert_to_hacefile(<<-MAKE)
        target: first.h
        	echo one

        target: second.h
        	echo two
        MAKE

      task = hacefile.tasks["target"]
      task.dependencies.should eq(["first.h", "second.h"])
      task.commands.should contain("echo two")
    end

    it "does not create tasks out of pattern rules" do
      hacefile = convert_to_hacefile(<<-MAKE)
        %.o: %.c
        	cc -c $<

        real:
        	touch real
        MAKE

      hacefile.tasks.has_key?("%.o").should be_false
      hacefile.tasks.has_key?("real").should be_true
    end

    it "drops order-only prerequisites" do
      hacefile = convert_to_hacefile(<<-MAKE)
        site: content | builddir
        	cp -r content site
        MAKE

      hacefile.tasks["site"].dependencies.should eq(["content"])
    end

    it "strips comments everywhere" do
      hacefile = convert_to_hacefile(<<-MAKE)
        # top comment
        VAR = value # trailing comment
        task: # comment after colon
        	realcmd # not part of the command
        MAKE

      hacefile.variables["VAR"].should eq("value")
      hacefile.tasks["task"].commands.should eq("realcmd")
    end

    it "unescapes hash signs" do
      hacefile = convert_to_hacefile("ESC = a \\# b\n")
      hacefile.variables["ESC"].should eq("a # b")
    end

    it "joins variable definitions spanning several lines" do
      hacefile = convert_to_hacefile("LIST = one \\\n     two \\\n     three\n")
      hacefile.variables["LIST"].should eq("one two three")
    end

    it "keeps recipe backslash continuations verbatim for the shell" do
      hacefile = convert_to_hacefile("t:\n\techo foo \\\n     bar\n")
      hacefile.tasks["t"].commands.should contain("\\\n")
    end

    it "strips @ prefixes and approximates - prefixes" do
      hacefile = convert_to_hacefile("t:\n\t@silentcmd\n\t-riskycmd\n")
      commands = hacefile.tasks["t"].commands.split("\n")
      commands[0].should eq("silentcmd")
      commands[1].should eq("(riskycmd) || true")
    end

    it "ignores unsupported directives without aborting" do
      hacefile = convert_to_hacefile(<<-MAKE)
        include other.mk

        ifneq ($(OS),Windows)

        still:
        	touch still
        MAKE

      hacefile.tasks.has_key?("still").should be_true
    end

    it "skips static pattern rules" do
      hacefile = convert_to_hacefile(<<-MAKE)
        objs = a.o b.o

        $(objs): %.o: %.c
        	cc -c $<

        real:
        	touch real
        MAKE

      hacefile.tasks.has_key?("real").should be_true
    end

    it "converts pattern rules into patterns entries" do
      yaml = MakefileConverter.convert(<<-MAKE)
        app: main.o
        	cc -o $@ $^

        %.o: %.c
        	cc -c $< stem=$*
        MAKE

      yaml.should contain("patterns:")
      yaml.should contain(%(outputs: ["%.o"]))
      yaml.should contain(%(dependencies: ["%.c"]))
      yaml.should contain(%({{ self["stem"] }}))
    end

    it "splits multi target pattern rules into separate entries" do
      yaml = MakefileConverter.convert(<<-MAKE)
        %.a %.b: %.src
        	generate $@
        MAKE

      yaml.scan(/outputs:/).size.should eq(2)
    end

    it "drops pattern rules without a recipe" do
      hacefile = convert_to_hacefile(<<-MAKE)
        plain:
        	touch plain

        %.o: %.c
        MAKE

      hacefile.tasks.has_key?("plain").should be_true
    end

    it "is deterministic" do
      content = "CC = gcc\nall:\n\t$(CC)\n"
      MakefileConverter.convert(content).should eq(MakefileConverter.convert(content))
    end
  end

  describe "runtime integration" do
    it "loads a Makefile through HaceFile.load_file" do
      with_scenario("makefile_auto", keep: ["Makefile"]) do
        hacefile = HaceFile.load_file("Makefile")
        hacefile.tasks["show"].commands.should contain("the message is: auto detected")
      end
    end

    it "expands automatic variables during load" do
      with_scenario("makefile_convert", keep: ["Makefile", "sources"]) do
        hacefile = HaceFile.load_file("Makefile")
        hacefile.tasks["hello"].commands.should eq("gcc -o hello main.o")
      end
    end
  end
end

describe "Makefile CLI support" do
  it "prints converted YAML with --convert" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("makefile_auto", keep: ["Makefile"]) do
      Process.run(HACE_BIN, ["--quiet", "--convert"], output: output, error: error)
    end
    result = output.to_s
    result.should contain("variables:")
    result.should contain("auto detected")
    result.should contain("tasks:")
  end

  it "runs a project straight off its Makefile via auto-detection" do
    output = IO::Memory.new
    error = IO::Memory.new
    with_scenario("makefile_auto", keep: ["Makefile"]) do
      Process.run(HACE_BIN, ["--dry-run", "show"], output: output, error: error)
    end
    (output.to_s + error.to_s).should contain(%(echo "the message is: auto detected"))
  end

  it "builds real files straight off a Makefile given with -f" do
    output = IO::Memory.new
    error = IO::Memory.new
    success = false
    with_scenario("makefile_convert", keep: ["Makefile", "sources"]) do
      status = Process.run(HACE_BIN, ["--quiet", "-f", "Makefile", "hello"],
        output: output, error: error)
      success = status.success?
      File.exists?("hello").should be_true
      # Remove build artifacts so they never end up committed by accident.
      File.delete?("hello")
      File.delete?("main.o")
    end
    success.should be_true
  end

  it "builds through pattern rules converted from a Makefile" do
    output = IO::Memory.new
    error = IO::Memory.new
    success = false
    with_scenario("makefile_pattern", keep: ["Makefile", "main.c", "util.c"]) do
      status = Process.run(HACE_BIN, ["--quiet", "-f", "Makefile", "app"],
        output: output, error: error)
      success = status.success?
      unless success
        puts output.to_s
        puts error.to_s
      end
      File.exists?("app").should be_true
      File.exists?("main.o").should be_true
      File.delete?("app")
      File.delete?("main.o")
      File.delete?("util.o")
    end
    success.should be_true
  end
end
