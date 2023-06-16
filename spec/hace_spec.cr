require "./spec_helper"
include Hace

describe Hace do
end

describe "parse_file" do
  it "should parse the tasks section" do
    parsed = parse_file("spec/testcases/basic/Hacefile.yml")
    parsed["tasks"].as_h.keys.should eq ["foo"]
  end
end
