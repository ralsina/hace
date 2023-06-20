require "./spec_helper"
include Hace

def with_scenario(name, keep = [] of String, &)
  logs = IO::Memory.new
  Log.setup(:debug, Log::IOBackend.new(io: logs)) # Helps for coverage
  # ::logs = IO::Memory.new
  # Log.setup(:debug, Log::IOBackend.new(io: logs, formatter: Log::ShortFormat))
  Dir.cd("spec/testcases/#{name}") do
    File.delete?(".croupier")
    Dir.glob("*").each do |f|
      File.delete?(f) unless f == "Hacefile.yml" || keep.includes?(f)
    end
    TaskManager.cleanup
    yield
  end
end

describe Hace do
  describe "HaceFile" do
    it "should parse the tasks section" do
      with_scenario("basic") do
        f = HaceFile.from_yaml(File.read("Hacefile.yml"))
        f.tasks.keys.should eq ["foo", "phony"]
        f.tasks["foo"].@phony.should be_false
        f.tasks["foo"].@dependencies.should eq ["bar"]

        f.tasks["phony"].@phony.should be_true
        f.tasks["phony"].@dependencies.empty?.should be_true
      end
    end

    it "should create tasks for all tasks" do
      with_scenario("basic") do
        HaceFile.from_yaml(File.read("Hacefile.yml")).gen_tasks
        TaskManager.tasks.keys.should eq ["foo", "phony"]

        TaskManager.tasks["foo"].@outputs.should eq ["foo"]
        TaskManager.tasks["phony"].@outputs.empty?.should be_true
      end
    end

    it "should parse the variables section" do
      with_scenario("variables") do
        f = HaceFile.from_yaml(File.read("Hacefile.yml"))
        f.variables.keys.should eq ["i", "s", "foo"]
        f.variables["i"].should eq 3
        f.variables["s"].should eq "string"
        f.variables["foo"].as_h.should eq({"bar" => "bat", "foo" => 86})
      end
    end

    it "should parse the env section" do
      with_scenario("env") do
        f = HaceFile.from_yaml(File.read("Hacefile.yml"))
        f.env.should eq({"barfile" => "bar", "bat" => nil})
      end
    end

    it "should support tasks with multiple outputs" do
      with_scenario("multi-output") do
        f = HaceFile.from_yaml(File.read("Hacefile.yml"))
        f.gen_tasks

        f.tasks.keys.should eq ["foo"]
        f.tasks["foo"].@outputs.should eq ["bar", "bat"]
        TaskManager.tasks.keys.should eq ["bar", "bat"]
      end
    end
  end

  describe "run" do
    it "fails without a Hacefile.yml" do
      Dir.cd("spec/testcases/") do
        expect_raises(Exception, "No Hacefile 'Hacefile.yml' found") do
          HaceFile.run
        end
      end
    end

    it "should run all tasks" do
      with_scenario("basic") do
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run
        File.read("foo").should eq "make foo out of bar\nquux\n"
        File.read("bat").should eq "bat\n"
      end
    end

    it "should fail with unknown target" do
      with_scenario("basic") do
        expect_raises(Exception, "sarasa") do
          HaceFile.run(arguments: ["sarasa"])
        end
      end
    end

    it "should be able to run just a task" do
      with_scenario("basic") do
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run(arguments: ["foo"])
        File.exists?("foo").should be_true
        File.exists?("bat").should be_false
        File.read("foo").should eq "make foo out of bar\nquux\n"
      end
    end

    it "should do nothing when running a second time" do
      with_scenario("run_all") do
        File.open("bar", "w") do |io|
          io << "1111"
        end
        HaceFile.run # This should put "1111" in "foo"
        TaskManager.tasks.values.select(&.stale?).empty?.should be_true
        File.read("foo").should eq "1111"
        # This should NOT put "2222" in "foo" because the tasks have ran
        File.open("bar", "w") do |io|
          io << "2222"
        end
        HaceFile.run
        File.read("foo").should eq "1111"
      end
    end

    it "should run normally when running a second time with run_all=true" do
      with_scenario("run_all") do
        File.open("bar", "w") do |io|
          io << "1111"
        end
        HaceFile.run # This should put "1111" in "foo"
        TaskManager.tasks.values.select(&.stale?).empty?.should be_true
        File.read("foo").should eq "1111"
        # This should put "2222" in "foo" because of run_all
        File.open("bar", "w") do |io|
          io << "2222"
        end
        HaceFile.run(run_all: true)
        File.read("foo").should eq "2222"
      end
    end

    it "should be able to run just a phony task" do
      with_scenario("basic") do
        HaceFile.run(arguments: ["phony"])
        File.exists?("foo").should be_false
        File.exists?("bat").should be_true
        File.read("bat").should eq "bat\n"
      end
    end

    # FIXME: have not figured out how to assrt on the logs
    # it "should warn of phony tasks with outputs" do
    #   with_scenario("basic") do
    #     HaceFile.run(arguments: ["phony"])
    #     logs.to_s.includes?("phony task 'phony' has outputs").should be_true
    #   end
    # end

    it "should expand variables in commands" do
      with_scenario("variables") do
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run
        File.read("foo").should eq "make foo out of bat at 3\nquux\n"
      end
    end

    it "should expand environment variables in commands" do
      with_scenario("env") do
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run
        File.read("foo").should eq "make foo out of bar\nquux\n"
        # This is empty because $bat is unset
        File.read("bat").should eq "\n"
      end
    end

    it "should run tasks with multiple outputs once" do
      with_scenario("multi-output") do
        HaceFile.run

        File.read("bar").should eq "bar\n"
        File.read("bat").should eq "bat\n"
        # Should only have ran once
        File.read("counter").should eq "running\n"
      end
    end

    it "should run tasks with always_run every time" do
      with_scenario("always-run") do
        HaceFile.run
        TaskManager.cleanup
        HaceFile.run
        # Should only have ran twice
        File.read("counter").should eq "running\nrunning\n"
      end
    end

    it "should always run tasks without dependencies" do
      with_scenario("no-deps") do
        HaceFile.run
        # Should have ran once
        File.read("foo").should eq "running\n"
        TaskManager.cleanup
        HaceFile.run
        # Should have ran twice
        File.read("foo").should eq "running\nrunning\n"
      end
    end

    it "should not run things if using dry_run" do
      with_scenario("no-deps") do
        HaceFile.run(dry_run: true)
        # Should not have actually ran
        File.exists?("foo").should be_false
      end
    end

    it "should error out if a command fails" do
      with_scenario("failure") do
        expect_raises(Exception, "Command failed: exit 1 when running /bin/false") do
          HaceFile.run
        end
      end
    end

    it "should not run later tasks if a dependency fails" do
      with_scenario("failed-chain") do
        expect_raises(Exception, "Command failed: exit 1 when running /bin/false") do
          HaceFile.run
        end
        File.exists?("foo").should be_false
        File.exists?("bar").should be_false
        File.exists?("bat").should be_false
      end
    end

    it "should run with a named file" do
      with_scenario("filename", keep: ["foobar"]) do
        expect_raises(Exception) do
          HaceFile.run.should eq 0
        end
        HaceFile.run(filename: "foobar")
      end
    end

    it "should not run anything on question mode" do
      with_scenario("no-deps") do
        HaceFile.run(question: true).should eq 1
        # Should not have actually ran
        File.exists?("foo").should be_false
      end
    end
  end
end
