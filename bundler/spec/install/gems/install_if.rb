require "spec_helper"

describe "bundle install with install_if conditionals" do
  it "follows the install_if DSL" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      install_if(lambda { true }) do
        gem "activesupport", "2.3.5"
      end
      gem "thin", :install_if => false
      install_if(lambda { false }) do
        gem "foo"
      end
      gem "rack"
    G

    should_be_installed("rack 1.0", "activesupport 2.3.5")
    should_not_be_installed("thin")
    should_not_be_installed("foo")

    lockfile_should_be <<-L
      GEM
        remote: file:#{gem_repo1}/
        specs:
          activesupport (2.3.5)
          foo (1.0)
          rack (1.0.0)
          thin (1.0)
            rack

      PLATFORMS
        ruby

      DEPENDENCIES
        activesupport (= 2.3.5)
        foo
        rack
        thin

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end
