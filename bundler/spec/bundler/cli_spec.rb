require 'spec_helper'
require 'bundler/cli'

describe "bundle executable" do
  let(:source_uri) { "http://localgemserver.test" }

  it "returns non-zero exit status when passed unrecognized options" do
    bundle '--invalid_argument'
    expect(exitstatus).to_not be_zero
  end

  it "returns non-zero exit status when passed unrecognized task" do
    bundle 'unrecognized-tast'
    expect(exitstatus).to_not be_zero
  end

  it "looks for a binary and executes it if it's named bundler-<task>" do
    File.open(tmp('bundler-testtasks'), 'w', 0755) do |f|
      f.puts "#!/usr/bin/env ruby\nputs 'Hello, world'\n"
    end

    with_path_as(tmp) do
      bundle 'testtasks'
    end

    expect(exitstatus).to be_zero
    expect(out).to eq('Hello, world')
  end
end
