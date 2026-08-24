require "log"

module Hace
  # Converts basic GNU Makefiles into Hacefile.yml content.
  #
  # Supported subset:
  # - rules with prerequisites and tab-indented recipes
  # - multiple targets per rule (become multiple outputs)
  # - variables (=, :=, ::=, ?=, +=), with $(NAME) / ${NAME} references.
  #   Variable values are resolved eagerly (make's "undefined means empty"
  #   semantics apply, and recursive variables must be defined before use).
  # - `export VAR=value` becomes an `env:` entry
  # - a `SHELL` variable becomes the Hacefile `shell:` setting
  # - .PHONY and .DEFAULT_GOAL
  # - automatic variables: $@ $< $^ $? $* and $$ escaping
  # - pattern rules ("%.o: %.c"), emitted into a `patterns:` section
  #
  # Anything else (conditionals, functions like $(wildcard),
  # include, target-specific variables, static pattern rules, ...) produces a
  # warning and is skipped; conversion never aborts because of unsupported
  # constructs.
  module MakefileConverter
    extend self

    # Basenames that identify a Makefile for runtime detection.
    MAKEFILE_NAMES = %w[Makefile makefile GNUmakefile]

    # Matches make variable assignments. Checked before the rule regex so
    # "VAR := x" is never mistaken for a rule.
    private ASSIGNMENT_RE = /\A\s*(export\s+)?([\w.]+)\s*(::=|:=|\+=|\?=|=)(.*)\z/

    # Matches a rule line: targets, colon, prerequisites.
    private RULE_RE = /\A([^\t#=\s][^=#]*?):(.*)\z/

    # Target-specific variable assignment hiding in the prerequisite slot,
    # e.g. "target: CFLAGS = -g".
    private TSVAR_RE = /\A\s*(?:export\s+)?[\w.]+\s*(?:::?=|\+=|\?=|=)/

    # Single-pass reference translation. Order inside the alternation matters:
    # $$ must win over the single-character automatic variables.
    private REF_RE = /\$\$|\$([@<^?*!])|\$\(([^)]*)\)|\$\{([^}]*)\}/

    private DIRECTIVES = %w[include -include sinclude ifeq ifneq ifdef ifndef else endif define endef override undefine unexport vpath]

    def looks_like_makefile?(filename : String) : Bool
      MAKEFILE_NAMES.includes?(File.basename(filename))
    end

    # Convert Makefile *content* into Hacefile.yml content.
    def convert(content : String) : String
      result = parse(content)
      resolve_variables(result)
      translate_tasks(result)
      emit(result)
      report_warnings(result)
      result.output
    end

    # A make rule: one or more targets, prerequisites and a recipe. Rules
    # whose targets contain '%' are pattern rules; they are emitted into the
    # Hacefile's `patterns:` section instead of `tasks:`.
    private class Rule
      property targets : Array(String)
      property prerequisites : Array(String)
      property commands : Array(String)
      property line : Int32
      property? pattern : Bool = false

      def initialize(@targets : Array(String), @prerequisites : Array(String), @line : Int32)
        @commands = [] of String
      end

      def first_target : String
        @targets.first
      end
    end

    private class ParseResult
      property rules = [] of Rule
      property variables = {} of String => String
      property env = {} of String => String
      property phony = Set(String).new
      property default_goal : String? = nil
      property warnings = [] of String
      property output : String = ""
    end

    # ---- Parsing -----------------------------------------------------------

    private def parse(content : String) : ParseResult
      result = ParseResult.new
      current_rule : Rule? = nil
      lines = content.gsub("\r\n", "\n").gsub("\r", "\n").split("\n")

      index = 0
      while index < lines.size
        line = lines[index]
        lineno = index + 1
        if line.starts_with?('\t')
          line, index = gather_recipe_continuation(line, lines, index)
          current_rule = parse_recipe_line(line, current_rule, result, lineno)
        else
          logical_line, index = join_continuation(line, lines, index)
          current_rule = classify(logical_line, result, lineno)
        end
        index += 1
      end

      result
    end

    # Recipe lines keep backslash-newline sequences verbatim so the shell
    # interprets them exactly as it would under make; only the leading tab of
    # each continued physical line is dropped.
    private def gather_recipe_continuation(line : String, lines : Array(String), index : Int32) : {String, Int32}
      gathered = line
      while odd_trailing_backslashes?(gathered) && index + 1 < lines.size
        index += 1
        next_line = lines[index]
        next_line = next_line[1..] if next_line.starts_with?('\t')
        gathered = "#{gathered}\n#{next_line}"
      end
      {gathered, index}
    end

    private def parse_recipe_line(line : String, current_rule : Rule?, result : ParseResult, lineno : Int32) : Rule?
      rule = current_rule
      if rule.nil?
        result.warnings << "line #{lineno}: recipe commences before any target, ignoring"
        return nil
      end

      body = strip_comment(line[1..])
      rule.commands << process_prefixes(body, result, lineno)
      rule
    end

    # Non-recipe lines have their continuations replaced by a single space,
    # matching POSIX make behavior for variable definitions and rule lines.
    private def join_continuation(line : String, lines : Array(String), index : Int32) : {String, Int32}
      logical = line
      while odd_trailing_backslashes?(logical) && index + 1 < lines.size
        index += 1
        logical = logical.sub(/\s*\\+\z/, "") + " " + lines[index].lstrip(" \t")
      end
      {logical, index}
    end

    private def odd_trailing_backslashes?(line : String) : Bool
      count = 0
      line.chars.reverse_each do |char|
        break unless char == '\\'
        count += 1
      end
      count.odd?
    end

    private def strip_comment(line : String) : String
      line.size.times do |index|
        next unless line[index] == '#'
        backslashes = 0
        cursor = index - 1
        while cursor >= 0 && line[cursor] == '\\'
          backslashes += 1
          cursor -= 1
        end
        return line[0...index].gsub("\\#", "#") if backslashes.even?
      end
      line.gsub("\\#", "#")
    end

    private def process_prefixes(body : String, result : ParseResult, lineno : Int32) : String
      command = body.strip
      ignore_errors = false
      while command.starts_with?('@') || command.starts_with?('-') || command.starts_with?('+')
        ignore_errors = true if command.starts_with?('-')
        command = command[1..].lstrip
      end
      result.warnings << "line #{lineno}: '-' recipe prefix approximated with '|| true'" if ignore_errors
      ignore_errors ? "(#{command}) || true" : command
    end

    private def classify(line : String, result : ParseResult, lineno : Int32) : Rule?
      stripped = strip_comment(line)

      return nil if stripped.strip.empty?

      if assignment = stripped.match(ASSIGNMENT_RE)
        handle_assignment(assignment, result, lineno)
        return nil
      end

      if match = stripped.match(RULE_RE)
        return handle_rule(match, result, lineno)
      end

      directive = stripped.strip.split.first?.try { |word| word }
      if directive && DIRECTIVES.includes?(directive)
        result.warnings << "line #{lineno}: unsupported directive '#{directive}', ignoring"
      else
        result.warnings << "line #{lineno}: unrecognized line ignored: #{stripped.strip[0, 60]}"
      end
      nil
    end

    private def handle_assignment(match : Regex::MatchData, result : ParseResult, lineno : Int32)
      name = match[2]
      operator = match[3]
      value = match[4].strip

      case
      when match[1]? # export VAR=value
        result.env[name] = value
      when name == ".DEFAULT_GOAL"
        result.default_goal = value.empty? ? nil : value
      when operator == "+=" # VAR += value
        result.variables[name] = append_variable(result, name, value)
      when operator == "?=" # VAR ?= value
        result.variables[name] ||= value
      else
        result.variables[name] = value
      end
    rescue ex
      result.warnings << "line #{lineno}: bad assignment ignored: #{ex.message}"
    end

    private def append_variable(result : ParseResult, name : String, value : String) : String
      existing = result.variables[name]?
      existing ? "#{existing} #{value}" : value
    end

    private def handle_rule(match : Regex::MatchData, result : ParseResult, lineno : Int32) : Rule?
      target_names = match[1].split
      prereq_text = match[2]

      # Double-colon rules ("foo:: dep") leave a stray leading colon in the
      # prerequisite slot; treat them as ordinary rules.
      if prereq_text.starts_with?(':')
        prereq_text = prereq_text[1..]
        result.warnings << "line #{lineno}: double-colon rule treated as an ordinary rule"
      end

      # A second colon in the prerequisite slot is make's static pattern rule
      # syntax ("objs: %.o: %.c"); hacé patterns cannot express it.
      if prereq_text.includes?(':')
        result.warnings << "line #{lineno}: static pattern rules are not supported, ignoring"
        return nil
      end

      # Target-specific variables ("target: VAR = x") hide behind a rule
      # shape; detect them on the raw prerequisite text.
      if prereq_text.matches?(TSVAR_RE)
        result.warnings << "line #{lineno}: target-specific variables are not supported, ignoring"
        return nil
      end

      normal_prereqs, order_only = split_order_only(prereq_text, result, lineno)

      unless order_only.empty?
        result.warnings << "line #{lineno}: order-only prerequisites ignored: #{order_only.join(" ")}"
      end

      target_names.reject! { |name| name == "&" }

      if target_names.any?(&.includes?('%'))
        rule = Rule.new(target_names, normal_prereqs, lineno)
        rule.pattern = true
        result.rules << rule
        return rule
      end

      if target_names.all?(&.starts_with?('.'))
        handle_special_targets(target_names, normal_prereqs, result, lineno)
        return nil
      end

      existing = result.rules.find { |candidate| candidate.targets == target_names }
      if existing
        existing.prerequisites |= normal_prereqs
        result.warnings << "line #{lineno}: merged duplicate rule for target(s): #{target_names.join(" ")}"
        return existing
      end

      rule = Rule.new(target_names, normal_prereqs, lineno)
      result.rules << rule
      rule
    end

    private def split_order_only(prereq_text : String, result : ParseResult, lineno : Int32)
      normal_part, _, order_part = prereq_text.partition("|")
      normal = normal_part.split.reject(&.empty?)
      order_only = order_part.split.reject(&.empty?)
      result.warnings << "line #{lineno}: '|' in prerequisites" if !order_only.empty?
      {normal, order_only}
    end

    private def handle_special_targets(targets : Array(String), prereqs : Array(String), result : ParseResult, lineno : Int32)
      if targets.includes?(".PHONY")
        prereqs.each { |name| result.phony << name }
      else
        result.warnings << "line #{lineno}: special target(s) ignored: #{targets.join(" ")}"
      end
    end

    # ---- Reference translation ---------------------------------------------

    # Resolve $(NAME)/${NAME} chains inside variable values eagerly, since
    # Hacefile variable values are static strings.
    private def resolve_variables(result : ParseResult)
      resolved = {} of String => String
      result.variables.each_key do |name|
        resolve_one(name, result, resolved, [] of String)
      end
      result.variables = resolved

      result.env.transform_values! { |value| resolve_in_value(value, result, resolved) }
    end

    private def resolve_one(name : String, result : ParseResult, resolved : Hash(String, String), stack : Array(String)) : String
      return resolved[name] if resolved.has_key?(name)
      return "" if stack.includes?(name)

      raw = result.variables.fetch(name) { return "" }
      stack.push(name)
      value = resolve_in_value(raw, result, resolved, stack)
      stack.pop
      resolved[name] = value
      value
    end

    private def resolve_in_value(text : String, result : ParseResult, resolved : Hash(String, String), stack : Array(String) = [] of String) : String
      text.gsub(REF_RE) do
        full = $0
        automatic = $1?
        paren_name = $2?
        brace_name = $3?

        if full == "$$"
          "$"
        elsif automatic
          result.warnings << "automatic variable '$#{automatic}' has no meaning in a variable value, kept literally" unless automatic.in?("!", "*")
          full
        elsif name = paren_name || brace_name
          if name.matches?(/\A\w+\z/)
            if resolved.has_key?(name)
              resolved[name]
            elsif result.variables.has_key?(name)
              resolve_one(name, result, resolved, stack.dup)
            else
              "" # make semantics: undefined variables expand to nothing
            end
          else
            result.warnings << "unsupported function call or reference '#{full}' left as-is"
            full
          end
        else
          full
        end
      end
    end

    # Translate references inside task prerequisites and recipes into Jinja
    # template syntax that hacé expands at task level, keeping CLI overrides
    # like `hace build DEBUG=1` working.
    #
    # ameba:disable Metrics/CyclomaticComplexity
    private def translate_task_refs(text : String, result : ParseResult) : String
      text.gsub(REF_RE) do
        full = $0
        automatic = $1?
        paren_name = $2?
        brace_name = $3?

        case
        when full == "$$"
          "$"
        when automatic == "@"
          %({{ self["outputs"][0] }})
        when automatic == "<"
          %({{ self["dependencies"][0] }})
        when automatic == "^" || automatic == "?"
          result.warnings << "'$?' translated as '$^' (staleness information is lost)" if automatic == "?"
          %({{ self["dependencies"] | join(" ") }})
        when automatic == "*"
          %({{ self["stem"] }})
        when automatic
          result.warnings << "unsupported automatic variable '$#{automatic}' kept literally"
          full
        when name = paren_name || brace_name
          if name.matches?(/\A\w+\z/)
            "{{ #{name} }}"
          else
            result.warnings << "unsupported function call or reference '#{full}' left as-is"
            full
          end
        else
          full
        end
      end
    end

    private def translate_tasks(result : ParseResult)
      result.rules.each do |rule|
        rule.prerequisites = rule.prerequisites.map { |dep| translate_task_refs(dep, result) }
        rule.commands = rule.commands.map { |command| translate_task_refs(command, result) }
      end
    end

    # ---- Emission ----------------------------------------------------------

    private def emit(result : ParseResult)
      io = IO::Memory.new

      unless result.env.empty?
        io << "env:\n"
        result.env.each do |name, value|
          io << "  #{scalar(name)}: #{scalar(value)}\n"
        end
      end

      if shell = result.variables.delete("SHELL")
        io << "shell: #{scalar(shell)}\n"
      end

      unless result.variables.empty?
        io << "variables:\n"
        result.variables.each do |name, value|
          io << "  #{scalar(name)}: #{scalar(value)}\n"
        end
      end

      default_task = pick_default(result)

      emit_patterns(io, result)

      io << "tasks:\n"
      result.rules.each do |rule|
        next if rule.pattern?
        emit_task(io, rule, result, default_task)
      end

      result.output = io.to_s
    end

    # Emit pattern rules into the `patterns:` section. Multi-target pattern
    # rules ("%.a %.b: %.c") become one entry per target pattern, sharing the
    # recipe. Pattern rules without a recipe are dropped with a warning.
    private def emit_patterns(io : IO, result : ParseResult)
      pattern_rules = result.rules.select(&.pattern?)
      return if pattern_rules.empty?

      io << "patterns:\n"
      pattern_rules.each do |rule|
        if rule.commands.empty?
          result.warnings << "line #{rule.line}: pattern rule without a recipe ignored: #{rule.targets.join(" ")}"
          next
        end
        rule.targets.each do |target|
          io << "  - outputs: [#{scalar(target)}]\n"
          unless rule.prerequisites.empty?
            deps = rule.prerequisites.map { |dep| scalar(dep) }.join(", ")
            io << "    dependencies: [#{deps}]\n"
          end
          emit_commands(io, rule)
        end
      end
    end

    private def pick_default(result : ParseResult) : String?
      concrete_rules = result.rules.reject(&.pattern?)
      goal = result.default_goal
      if goal
        known = concrete_rules.map(&.first_target)
        unless known.includes?(goal)
          result.warnings << ".DEFAULT_GOAL refers to unknown target '#{goal}', using the first rule instead"
          goal = nil
        end
      end
      goal || concrete_rules.first?.try(&.first_target)
    end

    private def emit_task(io : IO, rule : Rule, result : ParseResult, default_task : String?)
      name = rule.first_target
      io << "  #{scalar(name)}:\n"
      io << "    default: true\n" if name == default_task
      # Rules without a recipe are pure dependency aggregators in make
      # ("all: app"); they produce no files, so they map to phony tasks.
      phony = result.phony.includes?(name) || rule.commands.empty?
      io << "    phony: true\n" if phony
      if rule.targets.size > 1 && !phony
        io << "    outputs:\n"
        rule.targets.each { |target| io << "      - #{scalar(target)}\n" }
      end
      unless rule.prerequisites.empty?
        io << "    dependencies:\n"
        rule.prerequisites.each { |dep| io << "      - #{scalar(dep)}\n" }
      end
      emit_commands(io, rule)
    end

    private def emit_commands(io : IO, rule : Rule)
      if rule.commands.empty?
        io << "    commands: \"\"\n"
        return
      end

      io << "    commands: |-\n"
      rule.commands.each do |command|
        command.split("\n").each do |physical|
          io << (physical.empty? ? "\n" : "      #{physical}\n")
        end
      end
    end

    # Quote anything that is not a plain identifier-like word so YAML cannot
    # reinterpret values (e.g. version numbers as floats).
    private def scalar(value : String) : String
      return value if value.matches?(/\A[a-zA-Z_][a-zA-Z0-9_-]*\z/)
      escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n")
      "\"#{escaped}\""
    end

    private def report_warnings(result : ParseResult)
      result.warnings.uniq.each do |warning|
        Log.warn { "Makefile conversion: #{warning}" }
      end
    end
  end
end
