require "./hace"

cli = Commander::Command.new do |cmd|
  cmd.use = "hace"
  cmd.long = "hace makes things, like make"

  cmd.flags.add do |flag|
    flag.name = "run_all"
    flag.short = "-B"
    flag.long = "--always-make"
    flag.description = "Unconditionally run all tasks."
    flag.default = false
    flag.persistent = true
  end

  cmd.run do |options, arguments|
    Hace::HaceFile.run(
      arguments,
      run_all: options.@bool["run_all"]
    )
  end
end

Commander.run(cli, ARGV)
