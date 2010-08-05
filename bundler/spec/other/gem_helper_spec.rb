require "spec_helper"
require 'bundler/gem_helper'

describe "Bundler::GemHelper tasks" do
  context "determining gemspec" do
    it "interpolates the name when there is only one gemspec" do
      bundle 'gem test'
      app = bundled_app("test")
      helper = Bundler::GemHelper.new(app.to_s)
      helper.name.should == 'test'
    end

    it "should fail when there is no gemspec" do
      bundle 'gem test'
      app = bundled_app("test")
      FileUtils.rm(File.join(app.to_s, 'test.gemspec'))
      proc { Bundler::GemHelper.new(app.to_s) }.should raise_error(/Unable to determine name/)
    end

    it "should fail when there are two gemspecs and the name isn't specified" do
      bundle 'gem test'
      app = bundled_app("test")
      File.open(File.join(app.to_s, 'test2.gemspec'), 'w') {|f| f << ''}
      proc { Bundler::GemHelper.new(app.to_s) }.should raise_error(/Unable to determine name/)
    end
  end

  context "gem management" do
    before(:each) do
      bundle 'gem test'
      @app = bundled_app("test")
      gemspec = File.read("#{@app.to_s}/test.gemspec")
      File.open("#{@app.to_s}/test.gemspec", 'w') {|f| f << gemspec.gsub(/TODO/, '')}
      @helper = Bundler::GemHelper.new(@app.to_s)
    end

    it "builds" do
      @helper.build_gem
      bundled_app('test/pkg/test-0.0.0.gem').should exist
    end

    it "installs" do
      @helper.install_gem
      should_be_installed("test 0.0.0")
    end

    it "shouldn't push if there are uncommitted files" do
      proc { @helper.push_gem }.should raise_error(/files that need to be committed/)
    end

    it "pushes" do
      @helper.should_receive(:rubygem_push).with(bundled_app('test/pkg/test-0.0.0.gem').to_s)
      Dir.chdir(@app) {
        `git init --bare #{gem_repo1}`
        `git remote add origin file://#{gem_repo1}`
        `git commit -a -m"initial commit"`
      }
      @helper.push_gem
    end
  end
end
