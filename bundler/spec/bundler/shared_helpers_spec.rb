require "spec_helper"
require "bundler/shared_helpers"

describe Bundler::SharedHelpers do
  subject { Bundler::SharedHelpers }
  describe "#default_gemfile" do
    before do
      ENV["BUNDLE_GEMFILE"] = "/path/Gemfile"
    end
    context "Gemfile is present" do
      it "returns the Gemfile path" do
        expected_gemfile_path = Pathname.new("/path/Gemfile")
        expect(subject.default_gemfile).to eq(expected_gemfile_path)
      end
    end
    context "Gemfile is not present" do
      before do
        ENV["BUNDLE_GEMFILE"] = nil
      end
      it "raises a GemfileNotFound error" do
        expect { subject.default_gemfile }.to raise_error(Bundler::GemfileNotFound, "Could not locate Gemfile")
      end
    end
  end
  describe "#default_lockfile" do
    context "gemfile is gems.rb" do
      before do
        gemfile_path = Pathname.new("/path/gems.rb")
        allow(subject).to receive(:default_gemfile).and_return(gemfile_path)
      end
      it "returns the gems.locked path" do
        expected_lockfile_path = Pathname.new("/path/gems.locked")
        expect(subject.default_lockfile).to eq(expected_lockfile_path)
      end
    end
    context "is a regular Gemfile" do
      before do
        gemfile_path = Pathname.new("/path/Gemfile")
        allow(subject).to receive(:default_gemfile).and_return(gemfile_path)
      end
      it "returns the lock file path" do
        expected_lockfile_path = Pathname.new("/path/Gemfile.lock")
        expect(subject.default_lockfile).to eq(expected_lockfile_path)
      end
    end
  end
  describe "#default_bundle_dir" do
    context ".bundle does not exist" do
      it "returns nil" do
        expect(subject.default_bundle_dir).to eq(nil)
      end
    end
    context ".bundle is global .bundle" do
      before do
        Dir.mkdir ".bundle"
        global_rubygems_dir = Pathname.new("#{bundled_app}")
        allow(Bundler.rubygems).to receive(:user_home).and_return(global_rubygems_dir)
      end
      it "returns nil" do
        expect(subject.default_bundle_dir).to eq(nil)
      end
    end
    context ".bundle is not global .bundle" do
      before do
        Dir.mkdir ".bundle"
        global_rubygems_dir = Pathname.new("/path/rubygems")
        allow(Bundler.rubygems).to receive(:user_home).and_return(global_rubygems_dir)
      end
      it "returns the .bundle path" do
        expected_bundle_dir_path = Pathname.new("#{bundled_app}/.bundle")
        expect(subject.default_bundle_dir).to eq(expected_bundle_dir_path)
      end
    end
  end
  describe "#set_bundle_environment" do
    shared_examples_for "ENV['PATH'] gets set correctly" do
      before do
        Dir.mkdir ".bundle"
      end
      it "ensures bundle bin path is in ENV['PATH']" do
        subject.set_bundle_environment
        paths = (ENV["PATH"]).split(File::PATH_SEPARATOR)
        expect(paths.include? "#{Bundler.bundle_path}/bin").to eq(true)
      end
    end
    shared_examples_for "ENV['RUBYOPT'] gets set correctly" do
      it "ensures -rbundler/setup is at the beginning of ENV['RUBYOPT']" do
        subject.set_bundle_environment
        expect(ENV["RUBYOPT"].split(" ").first.include? "-rbundler/setup").to eq(true)
      end
    end
    shared_examples_for "ENV['RUBYLIB'] gets set correctly" do
      before do
        @ruby_lib_path = "stubbed_ruby_lib_dir"
        allow(File).to receive(:expand_path).and_return(@ruby_lib_path)
      end
      it "ensures bundler's ruby version lib path is in ENV['RUBYLIB']" do
        subject.set_bundle_environment
        paths = (ENV["RUBYLIB"]).split(File::PATH_SEPARATOR)
        expect(paths.include? @ruby_lib_path).to eq(true)
      end
    end
    it "calls the appropriate set methods" do
      expect(subject).to receive(:set_path)
      expect(subject).to receive(:set_rubyopt)
      expect(subject).to receive(:set_rubylib)
      subject.set_bundle_environment
    end
    context "ENV['PATH'] does not exist" do
      before { ENV.delete("PATH") }
      it_behaves_like "ENV['PATH'] gets set correctly"
    end
    context "ENV['PATH'] is empty" do
      before { ENV["PATH"] = "" }
      it_behaves_like "ENV['PATH'] gets set correctly"
    end
    context "ENV['PATH'] exists" do
      before { ENV["PATH"] = "/some_path/bin" }
      it_behaves_like "ENV['PATH'] gets set correctly"
    end
    context "ENV['PATH'] already contains the bundle bin path" do
      before do
        @bundle_path = "#{Bundler.bundle_path}/bin"
        ENV["PATH"] = @bundle_path
      end
      it_behaves_like "ENV['PATH'] gets set correctly"
      it "ENV['PATH'] should only contain one instance of bundle bin path" do
        subject.set_bundle_environment
        paths = (ENV["PATH"]).split(File::PATH_SEPARATOR)
        expect(paths.count(@bundle_path)).to eq(1)
      end
    end
    context "ENV['RUBYOPT'] does not exist" do
      before { ENV.delete("RUBYOPT") }
      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end
    context "ENV['RUBYOPT'] exists without -rbundler/setup" do
      before { ENV["RUBYOPT"] = "-I/some_app_path/lib" }
      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end
    context "ENV['RUBYOPT'] exists and contains -rbundler/setup" do
      before do
        ENV["RUBYOPT"] = "-rbundler/setup"
      end
      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end
    context "ENV['RUBYLIB'] does not exist" do
      before { ENV.delete("RUBYLIB") }
      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end
    context "ENV['RUBYLIB'] is empty" do
      before { ENV["PATH"] = "" }
      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end
    context "ENV['RUBYLIB'] exists" do
      before { ENV["PATH"] = "/some_path/bin" }
      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end
    context "ENV['RUBYLIB'] already contains the bundler's ruby version lib path" do
      before do
        @ruby_lib_path = "stubbed_ruby_lib_dir"
        allow(File).to receive(:expand_path).and_return(@ruby_lib_path)
        ENV["RUBYLIB"] = @ruby_lib_path
      end
      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
      it "ENV['RUBYLIB'] should only contain one instance of bundler's ruby version lib path" do
        subject.set_bundle_environment
        paths = (ENV["RUBYLIB"]).split(File::PATH_SEPARATOR)
        expect(paths.count(@ruby_lib_path)).to eq(1)
      end
    end
  end
  describe "#const_get_safely" do
    module TargetNamespace
      VALID_CONSTANT = 1
    end
    context "when the namespace does have the requested constant" do
      it "returns the value of the requested constant" do
        expect(subject.const_get_safely(:VALID_CONSTANT, TargetNamespace)).to eq(1)
      end
    end
    context "when the requested constant is passed as a string" do
      it "returns the value of the requested constant" do
        expect(subject.const_get_safely("VALID_CONSTANT", TargetNamespace)).to eq(1)
      end
    end
    context "when the namespace does not have the requested constant" do
      it "returns nil" do
        expect(subject.const_get_safely("INVALID_CONSTANT", TargetNamespace)).to eq(nil)
      end
    end
  end
end
