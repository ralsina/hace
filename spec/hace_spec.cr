require "./spec_helper"
include Hace

describe Hace do
  describe "HaceFile" do
    it "should parse the tasks section" do
      TaskManager.cleanup
      f = HaceFile.from_yaml(File.read("spec/testcases/basic/Hacefile.yml"))
      f.tasks.keys.should eq ["foo"]
    end

    it "should create tasks for all tasks" do
      TaskManager.cleanup
      HaceFile.from_yaml(File.read("spec/testcases/basic/Hacefile.yml")).gen_tasks
      TaskManager.tasks.keys.should eq ["foo"]
    end

    it "create the right tasks to do things" do
      TaskManager.cleanup
      Dir.cd("spec/testcases/basic") do
        f = HaceFile.from_yaml(File.read("Hacefile.yml"))
        f.gen_tasks
        File.delete?("foo")
        File.delete?("bar")
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        TaskManager.run_tasks
        File.read("foo").should eq "make foo out of bar\nquux\n"
      end
    end
  end

  describe "run" do
    it "should parse ./Hacefile.yml" do
      TaskManager.cleanup
      Dir.cd("spec/testcases/basic") do
        File.delete?("foo")
        File.delete?("bar")
        File.delete?(".croupier")
        File.open("bar", "w") do |io|
          io << "quux\n"
        end
        HaceFile.run
        File.read("foo").should eq "make foo out of bar\nquux\n"
      end
    end
  end

  it "should fail with unknown target" do
    TaskManager.cleanup
    File.delete?(".croupier")
    Dir.cd("spec/testcases/basic") do
      expect_raises(Exception, "sarasa") do
        HaceFile.run(arguments: ["sarasa"])
      end
    end
  end
end
