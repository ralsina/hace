require "./spec_helper"
include Hace

def with_scenario(name, &)
  Dir.cd("spec/testcases/#{name}") do
    Dir.glob("*").each do |f|
      File.delete?(f) unless f == "Hacefile.yml"
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
  end

  describe "run" do
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
        HaceFile.run(arguments: ["foo"])
        File.exists?("foo").should be_true
        File.exists?("bat").should be_false
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

    it "should expand variables in commands" do
      with_scenario("variables") do
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run
        File.read("foo").should eq "make foo out of bat at 3\nquux\n"
        File.read("bat").should eq "bat\n"
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
  end
end
