require "./hace"

cli = Commander::Command.new do |cmd|
  cmd.use = "hace"
  cmd.long = "hace makes things, like make"

  cmd.run do |options, arguments|
    Hace::HaceFile.run(options, arguments)
  end
end

Commander.run(cli, ARGV)
