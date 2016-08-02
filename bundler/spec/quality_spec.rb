# frozen_string_literal: true
require "spec_helper"

if defined?(Encoding) && Encoding.default_external.name != "UTF-8"
  # Poor man's ruby -E UTF-8, since it works on 1.8.7
  Encoding.default_external = Encoding.find("UTF-8")
end

describe "The library itself" do
  def check_for_spec_defs_with_single_quotes(filename)
    failing_lines = []

    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ /^ *(describe|it|context) {1}'{1}/
    end

    return if failing_lines.empty?
    "#{filename} uses inconsistent single quotes on lines #{failing_lines.join(", ")}"
  end

  def check_for_debugging_mechanisms(filename)
    debugging_mechanisms_regex = /
      (binding\.pry)|
      (debugger)|
      (sleep\s*\(?\d+)|
      (fit\s*\(?("|\w))
    /x

    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      if line =~ debugging_mechanisms_regex && !line.end_with?("# ignore quality_spec\n")
        failing_lines << number + 1
      end
    end

    return if failing_lines.empty?
    "#{filename} has debugging mechanisms (like binding.pry, sleep, debugger, rspec focusing, etc.) on lines #{failing_lines.join(", ")}"
  end

  def check_for_git_merge_conflicts(filename)
    merge_conflicts_regex = /
      <<<<<<<|
      =======|
      >>>>>>>
    /x

    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ merge_conflicts_regex
    end

    return if failing_lines.empty?
    "#{filename} has unresolved git merge conflicts on lines #{failing_lines.join(", ")}"
  end

  def check_for_tab_characters(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ /\t/
    end

    return if failing_lines.empty?
    "#{filename} has tab characters on lines #{failing_lines.join(", ")}"
  end

  def check_for_extra_spaces(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      next if line =~ /^\s+#.*\s+\n$/
      next if %w(LICENCE.md).include?(line)
      failing_lines << number + 1 if line =~ /\s+\n$/
    end

    return if failing_lines.empty?
    "#{filename} has spaces on the EOL on lines #{failing_lines.join(", ")}"
  end

  def check_for_expendable_words(filename)
    failing_line_message = []
    useless_words = /\b(actually|obviously|just|clearly|basically|really)\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = useless_words.match(line)
      failing_line_message << "#{filename} has '#{word_found}' on line #{number + 1}. Avoid using these kinds of weak modifiers."
    end

    failing_line_message unless failing_line_message.empty?
  end

  def check_for_specific_pronouns(filename)
    failing_line_message = []
    specific_pronouns = /\b(he|she|his|hers|him|her|himself|herself)\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = specific_pronouns.match(line)
      failing_line_message << "#{filename} has '#{word_found}' on line #{number + 1}. Use more generic pronouns in documentation."
    end

    failing_line_message unless failing_line_message.empty?
  end

  RSpec::Matchers.define :be_well_formed do
    match(&:empty?)

    failure_message do |actual|
      actual.join("\n")
    end
  end

  it "has no malformed whitespace" do
    exempt = /\.gitmodules|\.marshal|fixtures|vendor|ssl_certs|LICENSE/
    error_messages = []
    Dir.chdir(File.expand_path("../..", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_tab_characters(filename)
        error_messages << check_for_extra_spaces(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "uses double-quotes consistently in specs" do
    included = /spec/
    error_messages = []
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_spec_defs_with_single_quotes(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any leftover debugging or development mechanisms" do
    exempt = %r{quality_spec.rb|support/helpers}
    error_messages = []
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_debugging_mechanisms(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "does not include any unresolved merge conflicts" do
    error_messages = []
    exempt = %r{lock/lockfile_spec|quality_spec}
    Dir.chdir(File.expand_path("../", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_git_merge_conflicts(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of the documentation" do
    included = /ronn/
    error_messages = []
    Dir.chdir(File.expand_path("../../man", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "maintains language quality of sentences used in source code" do
    error_messages = []
    exempt = /vendor/
    Dir.chdir(File.expand_path("../../lib", __FILE__)) do
      `git ls-files -z`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "can still be built" do
    Dir.chdir(root) do
      begin
        gem_command! :build, "bundler.gemspec"
        expect(err).to be_empty, "bundler should build as a gem without warnings, but\n#{err}"
      ensure
        # clean up the .gem generated
        FileUtils.rm("bundler-#{Bundler::VERSION}.gem")
      end
    end
  end

  it "does not contain any warnings" do
    Dir.chdir(root.join("lib")) do
      exclusions = %w(
        bundler/capistrano.rb
        bundler/gem_tasks.rb
        bundler/vlad.rb
      )
      lib_files = `git ls-files -z`.split("\x0").grep(/\.rb$/) - exclusions
      lib_files.reject! {|f| f.start_with?("bundler/vendor") }
      lib_files.map! {|f| f.chomp(".rb") }
      sys_exec("ruby -w -I. ", :expect_err) do |input, _, _|
        lib_files.each do |f|
          input.puts "require '#{f}'"
        end
      end

      expect(@err.split("\n")).to be_well_formed
      expect(@out.split("\n")).to be_well_formed
    end
  end
end
