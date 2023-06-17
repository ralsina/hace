require "./spec_helper"
include Hace

describe Hace do
end

describe "parse_file" do
  it "should parse the tasks section" do
    f = HaceFile.from_yaml(File.read("spec/testcases/basic/Hacefile.yml"))
    f.tasks.keys.should eq ["foo"]
  end

  it "should create tasks for all tasks" do
    HaceFile.from_yaml(File.read("spec/testcases/basic/Hacefile.yml")).gen_tasks
    TaskManager.tasks.keys.should eq ["foo"]
  end

  it "should execute the command of a task" do
    Dir.cd("spec/testcases/basic") do
      f = HaceFile.from_yaml(File.read("Hacefile.yml"))
      f.gen_tasks
      File.delete?("foo")
      File.open("bar", "w") do |io|
        io << "quux\n"
      end
      TaskManager.run_tasks
      File.read("foo").should eq "make foo out of bar\nquux\n"
    end
  end
end
