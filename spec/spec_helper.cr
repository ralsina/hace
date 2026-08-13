require "spec"
require "file_utils"
require "../src/hace"
include Hace

# Run a block inside the spec/testcases/<name> scenario directory.
#
# Cleans generated files, then resets both Croupier's TaskManager and Hace's
# module-level state (VARIABLES, ENVIRONMENT, TASKS_WITH_CLI_ARGS) so that
# values injected by one scenario cannot leak into the next.
#
# `keep` lists filenames to preserve alongside Hacefile.yml (which is always
# kept). `extra_keep` is for files that a specific scenario must never delete,
# such as the `.env` used by the dotenv scenarios.
def with_scenario(name, keep = [] of String, extra_keep = [] of String, logs : IO::Memory = IO::Memory.new, &)
  Log.setup(:debug, Log::IOBackend.new(io: logs, formatter: Log::ShortFormat))
  Dir.cd("spec/testcases/#{name}") do
    File.delete?(".croupier") unless keep.includes? ".croupier"
    Dir.glob("*").each do |f|
      next if f == "Hacefile.yml" || keep.includes?(f) || extra_keep.includes?(f)
      if File.directory?(f)
        FileUtils.rm_rf(f)
      else
        File.delete?(f)
      end
    end
    TaskManager.cleanup
    Hace.reset_state
    yield
  end
end
