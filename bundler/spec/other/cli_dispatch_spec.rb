# frozen_string_literal: true

RSpec.describe "bundle command names" do
  it "work when given fully" do
    bundle "install"
    expect(err).to eq("Could not locate Gemfile")
    expect(out).not_to include("Ambiguous command")
  end

  it "work when not ambiguous" do
    bundle "ins"
    expect(err).to eq("Could not locate Gemfile")
    expect(out).not_to include("Ambiguous command")
  end

  it "print a friendly error when ambiguous" do
    bundle "in"
    expect(last_command.bundler_err).to eq("Ambiguous command in matches [info, init, inject, install]")
  end
end
