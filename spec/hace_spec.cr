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
      end
    end

    it "should create tasks for all tasks" do
      with_scenario("basic") do
        HaceFile.from_yaml(File.read("Hacefile.yml")).gen_tasks
        TaskManager.tasks.keys.should eq ["foo", "phony"]
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
  end
end
