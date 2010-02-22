require File.expand_path('../../spec_helper', __FILE__)

describe "Bundler.setup" do
  it "uses BUNDLE_GEMFILE to locate the gemfile if present" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    gemfile bundled_app('4realz'), <<-G
      source "file://#{gem_repo1}"
      gem "activesupport", "2.3.5"
    G

    ENV['BUNDLE_GEMFILE'] = bundled_app('4realz').to_s
    bundle :install

    should_be_installed "activesupport 2.3.5"
  end

  describe "cripping rubygems" do
    it "replaces #gem with an alternative that raises when appropriate" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      run <<-R
        begin
          gem "activesupport"
          puts "FAIL"
        rescue LoadError
          puts "WIN"
        end
      R

      out.should == "WIN"
    end

    it "replaces #gem with an alternative that raises when appropriate 2" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "0.9.1"
      G

      run <<-R
        begin
          gem "rack", "1.0.0"
          puts "FAIL"
        rescue LoadError
          puts "WIN"
        end
      R

      out.should == "WIN"
    end
  end

  describe "with paths" do
    it "activates the gems in the path source" do
      pending
      system_gems "rack-1.0.0"

      build_lib "rack", "1.0.0" do |s|
        s.write "lib/rack.rb", "puts 'WIN'"
      end

      gemfile <<-G
        path "#{lib_path('rack-1.0.0')}"
        source "file://#{gem_repo1}"
        gem "rack"
      G

      run "require 'rack'"
      out.should == "WIN"
    end
  end

  describe "when locked" do
    it "regenerates .bundle/environment.rb if it does not exist" do
      system_gems "rack-1.0.0"

      gemfile <<-G
        gem "rack"
      G

      bundle :lock

      bundled_app('.bundle').rmtree

      should_be_installed "rack 1.0.0"
      bundled_app('.bundle/environment.rb').should exist
    end
  end

  describe "when excluding groups" do
    it "doesn't change the resolve if --without is used" do
      install_gemfile <<-G, :without => :rails
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      install_gems "activesupport-2.3.5"

      should_be_installed "activesupport 2.3.2", :groups => :default
    end
  end
end
