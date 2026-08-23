require "./spec_helper"
include Hace

describe "Variables" do
  it "should preserve string values that look like YAML scalars" do
    # The old implementation expanded variables by rendering their YAML
    # representation and re-parsing it, which turned the string "null"
    # into nil (and "true" into a bool). Values must survive verbatim.
    with_scenario("variables-typed") do
      HaceFile.run
      content = File.read("typed.txt")
      content.should contain "[null][true][7]"
      content.should contain "one-two-"
    end
  end

  it "should apply KEY=value command line overrides to templates" do
    with_scenario("variables") do
      File.write("bar", "quux\n")
      HaceFile.run(arguments: ["i=9"])
      File.read("foo").should contain "at 9"
    end
  end

  it "should let Hacefile defaults win when no override is given" do
    with_scenario("variables") do
      File.write("bar", "quux\n")
      HaceFile.run
      File.read("foo").should contain "at 3"
    end
  end
end
