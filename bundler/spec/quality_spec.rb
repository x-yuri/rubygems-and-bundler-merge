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

    unless failing_lines.empty?
      "#{filename} uses inconsistent single quotes on lines #{failing_lines.join(", ")}"
    end
  end

  def check_for_tab_characters(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      failing_lines << number + 1 if line =~ /\t/
    end

    unless failing_lines.empty?
      "#{filename} has tab characters on lines #{failing_lines.join(", ")}"
    end
  end

  def check_for_extra_spaces(filename)
    failing_lines = []
    File.readlines(filename).each_with_index do |line, number|
      next if line =~ /^\s+#.*\s+\n$/
      next if %w(LICENCE.md).include?(line)
      failing_lines << number + 1 if line =~ /\s+\n$/
    end

    unless failing_lines.empty?
      "#{filename} has spaces on the EOL on lines #{failing_lines.join(", ")}"
    end
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

  it "can still be built" do
    Dir.chdir(root) do
      `gem build bundler.gemspec`
      expect($?).to eq(0)

      # clean up the .gem generated
      system("rm bundler-#{Bundler::VERSION}.gem")
    end
  end

  it "does not contain any warnings" do
    Dir.chdir(root.join("lib"))
    exclusions = %r{bundler/capistrano\.rb|bundler/vlad\.rb|bundler/gem_tasks\.rb|tmp/rubygems}
    lib_files = `git ls-files -z -- **/*.rb`.split("\x0").reject {|f| f =~ exclusions }
    sys_exec("ruby -w -I. ", :expect_err) do |input|
      lib_files.each do |f|
        input.puts "require '#{f.gsub(/\.rb$/, "")}'"
      end
    end

    expect(@err.split("\n")).to eq([])
    expect(@out).to eq("")
  end
end
