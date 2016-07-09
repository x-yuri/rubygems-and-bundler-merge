# frozen_string_literal: true
require "spec_helper"

describe "Resolving" do
  before :each do
    @index = an_awesome_index
  end

  it "resolves a single gem" do
    dep "rack"

    should_resolve_as %w(rack-1.1)
  end

  it "resolves a gem with dependencies" do
    dep "actionpack"

    should_resolve_as %w(actionpack-2.3.5 activesupport-2.3.5 rack-1.0)
  end

  it "resolves a conflicting index" do
    @index = a_conflict_index
    dep "my_app"
    should_resolve_as %w(activemodel-3.2.11 builder-3.0.4 grape-0.2.6 my_app-1.0.0)
  end

  it "resolves a complex conflicting index" do
    @index = a_complex_conflict_index
    dep "my_app"
    should_resolve_as %w(a-1.4.0 b-0.3.5 c-3.2 d-0.9.8 my_app-1.1.0)
  end

  it "resolves a index with conflict on child" do
    @index = index_with_conflict_on_child
    dep "chef_app"
    should_resolve_as %w(berkshelf-2.0.7 chef-10.26 chef_app-1.0.0 json-1.7.7)
  end

  it "resolves a index with root level conflict on child" do
    @index = a_index_with_root_conflict_on_child
    dep "i18n", "~> 0.4"
    dep "activesupport", "~> 3.0"
    dep "activerecord", "~> 3.0"
    dep "builder", "~> 2.1.2"
    should_resolve_as %w(activesupport-3.0.5 i18n-0.4.2 builder-2.1.2 activerecord-3.0.5 activemodel-3.0.5)
  end

  it "raises an exception if a child dependency is not resolved" do
    @index = a_unresovable_child_index
    dep "chef_app_error"
    expect do
      resolve
    end.to raise_error(Bundler::VersionConflict)
  end

  it "should throw error in case of circular dependencies" do
    @index = a_circular_index
    dep "circular_app"

    expect do
      resolve
    end.to raise_error(Bundler::CyclicDependencyError, /please remove either gem 'bar' or gem 'foo'/i)
  end

  # Issue #3459
  it "should install the latest possible version of a direct requirement with no constraints given" do
    @index = a_complicated_index
    dep "foo"
    should_resolve_and_include %w(foo-3.0.5)
  end

  # Issue #3459
  it "should install the latest possible version of a direct requirement with constraints given" do
    @index = a_complicated_index
    dep "foo", ">= 3.0.0"
    should_resolve_and_include %w(foo-3.0.5)
  end

  it "takes into account required_ruby_version" do
    @index = build_index do
      gem "foo", "1.0.0" do
        dep "bar", ">= 0"
      end

      gem "foo", "2.0.0" do |s|
        dep "bar", ">= 0"
        s.required_ruby_version = "~> 2.0.0"
      end

      gem "bar", "1.0.0"

      gem "bar", "2.0.0" do |s|
        s.required_ruby_version = "~> 2.0.0"
      end
    end
    dep "foo"

    deps = []
    @deps.each do |d|
      deps << Bundler::DepProxy.new(d, "ruby")
    end

    should_resolve_and_include %w(foo-1.0.0 bar-1.0.0), [{}, [], Bundler::RubyVersion.new("1.8.7", nil, nil, nil)]
  end

  context "conservative" do
    before :each do
      @index = build_index do
        gem("foo", "1.3.7") { dep "bar", "~> 2.0" }
        gem("foo", "1.3.8") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.3") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.4") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.5") { dep "bar", "~> 2.1" }
        gem("foo", "1.5.0") { dep "bar", "~> 2.1" }
        gem("foo", "1.5.1") { dep "bar", "~> 3.0" }
        gem "bar", %w(2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 3.0.0)
      end
      dep "foo"

      @locked = locked(%w(foo 1.4.3), %w(bar 2.0.3))
    end

    it "resolves all gems to latest patch" do
      # strict is not set, so bar goes up a minor version due to dependency from foo 1.4.5
      should_consv_resolve_and_include :patch, [], %w(foo-1.4.5 bar-2.1.1)
    end

    it "resolves all gems to latest patch strict" do
      # strict is set, so foo can only go up to 1.4.4 to avoid bar going up a minor version, and bar can go up to 2.0.5
      should_consv_resolve_and_include [:patch, :strict], [], %w(foo-1.4.4 bar-2.0.5)
    end

    it "resolves all gems to latest patch minimal" do
      # minimal is set, so foo goes up the next available to 1.4.4 and bar goes up to next available 2.0.4
      should_consv_resolve_and_include [:patch, :minimal], [], %w(foo-1.4.4 bar-2.0.4)
    end

    it "resolves foo only to latest patch - same dependency case" do
      @locked = locked(%w(foo 1.3.7), %w(bar 2.0.3))
      # bar is locked, and the lock holds here because the dependency on bar doesn't change on the matching foo version.
      should_consv_resolve_and_include :patch, ["foo"], %w(foo-1.3.8 bar-2.0.3)
    end

    it "resolves foo only to latest patch - changing dependency case" do
      # bar is locked, but locks don't apply to _changing_ dependencies and since the dependency of the
      # selected foo gem changes, the latest matching of bar-2.1.1
      # (this could be considered a bug, but possibly hard to solve for)
      should_consv_resolve_and_include :patch, ["foo"], %w(foo-1.4.5 bar-2.1.1)
    end

    it "resolves foo only to latest patch strict" do
      # adding strict helps solve the possibly unexpected behavior of bar changing in the prior test case,
      # because no versions will be returned for bar ~> 2.1, so the engine falls back to ~> 2.0 (turn on
      # debugging to see this happen).
      should_consv_resolve_and_include [:patch, :strict], ["foo"], %w(foo-1.4.4 bar-2.0.3)
    end

    it "resolves bar only to latest patch" do
      # bar is locked, so foo can only go up to 1.4.4
      should_consv_resolve_and_include :patch, ["bar"], %w(foo-1.4.3 bar-2.0.5)
    end

    it "resolves all gems to latest minor" do
      # strict is not set, so bar goes up a major version due to dependency from foo 1.4.5
      should_consv_resolve_and_include :minor, [], %w(foo-1.5.1 bar-3.0.0)
    end

    it "resolves all gems to latest minor strict" do
      # strict is set, so foo can only go up to 1.5.0 to avoid bar going up a major version
      should_consv_resolve_and_include [:minor, :strict], [], %w(foo-1.5.0 bar-2.1.1)
    end

    it "resolves all gems to latest minor minimal" do
      # minimal is set, and it takes precedence over minor. not sure what is the PoLS in this case. Not sure
      # if minimal is a great option in the first place. It exists to help a case where there are many, many
      # versions and I'd rather go from 1.0.2 to 1.0.3 instead of 1.0.45. But, we could consider killing the
      # minimal option altogether. If that's what you need, use the Gemfile dependency.
      should_consv_resolve_and_include [:minor, :minimal], [], %w(foo-1.4.4 bar-2.0.4)
    end

    it "will not revert to a previous version"
    it "has taken care of all MODOs"
    it "bring over all sort/filter specs from bundler-patch"
  end
end
