require "./spec_helper"
include Hace

describe Hace do
end

describe "parse_file" do
  it "should parse the tasks section" do
    parsed = parse_file("spec/testcases/basic/Hacefile.yml")
    parsed["tasks"].as_h.keys.should eq ["foo"]
  end

  it "should create tasks for all tasks" do
    create_tasks(parse_file("spec/testcases/basic/Hacefile.yml"))
    TaskManager.tasks.keys.should eq ["foo"]
    TaskManager.tasks["foo"].to_s.should eq \
      "Commands: \n" + "  echo \"make foo out of bar\" > foo\n" + "  cat bar >> foo"
  end

  it "should execute the command of a task" do
    Dir.cd("spec/testcases/basic") do
      create_tasks(parse_file("Hacefile.yml"))
      File.delete?("foo")
      File.open("bar", "w") do |io|
        io << "quux\n"
      end
      TaskManager.run_tasks
      File.read("foo").should eq "make foo out of bar\nquux\n"
    end
  end
end
