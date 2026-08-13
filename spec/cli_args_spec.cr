require "./spec_helper"
include Hace

describe "CLI Args Passthrough" do
  describe "explicit {{CLI_ARGS}}" do
    it "should replace template with shell-quoted args" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["explicit"], cli_args: ["--verbose", "--tag=fast"])
        File.read("explicit.txt").strip.should eq "Args: --verbose --tag=fast"
      end
    end

    it "should handle empty CLI_ARGS" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["empty_args"], cli_args: [] of String)
        File.read("empty.txt").strip.should eq "No args: ''"
      end
    end
  end

  describe "{{CLI_ARGS_LIST}}" do
    it "should be iterable in Jinja" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["list_form"], cli_args: ["--a", "--b"])
        content = File.read("list.txt")
        content.should contain "Count: 2"
        content.should contain "- --a"
        content.should contain "- --b"
      end
    end

    it "should handle empty list" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["list_form"], cli_args: [] of String)
        content = File.read("list.txt")
        content.should contain "Count: 0"
      end
    end
  end

  describe "auto-append behavior" do
    it "should append to last command when no explicit usage" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["auto_append"], cli_args: ["--verbose"])
        content = File.read("auto.txt")
        # Last command "echo crystal spec" should have --verbose appended
        content.should contain "crystal spec --verbose"
      end
    end

    it "should not append when CLI_ARGS is empty" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["auto_append"], cli_args: [] of String)
        content = File.read("auto.txt")
        # Should not have trailing space or args
        content.strip.should eq "Starting\ncrystal spec"
      end
    end

    it "should append only to the last command in multi-command tasks" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["multi_cmd"], cli_args: ["--flag"])
        content = File.read("multi.txt")
        # Only the last command should have --flag appended
        content.should contain "Step 1"
        content.should contain "Step 2"
        content.should contain "Final step --flag"
      end
    end
  end

  describe "explicit placement" do
    it "should place CLI_ARGS where specified" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["middle"], cli_args: ["--verbose"])
        content = File.read("middle.txt")
        content.should contain "Before"
        content.should contain "crystal spec --verbose"
        content.should contain "After"
      end
    end

    it "should not auto-append when explicit CLI_ARGS is used" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["explicit"], cli_args: ["--verbose"])
        content = File.read("explicit.txt")
        # Should only appear where explicitly placed
        content.strip.should eq "Args: --verbose"
      end
    end
  end

  describe "shell quoting" do
    it "should properly quote args with spaces" do
      with_scenario("cli_args") do
        HaceFile.run(arguments: ["explicit"], cli_args: ["--tag=slow test"])
        content = File.read("explicit.txt")
        # Should be properly quoted for shell
        content.should contain "'--tag=slow test'"
      end
    end

    it "should properly quote args with special characters" do
      with_scenario("cli_args") do
        # Use patterns that test quoting without shell variable expansion
        # Note: $VAR in double-quoted echo will still expand, but *.cr glob won't
        HaceFile.run(arguments: ["explicit"], cli_args: ["--pattern=*.cr", "--with-brackets=[test]"])
        content = File.read("explicit.txt")
        # Glob pattern should be quoted and not expanded
        content.should contain "'--pattern=*.cr'"
        # Brackets should be quoted
        content.should contain "'--with-brackets=[test]'"
      end
    end
  end
end
