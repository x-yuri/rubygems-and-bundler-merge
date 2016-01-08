require "spec_helper"
require "bundler/shared_helpers"

module TargetNamespace
  VALID_CONSTANT = 1
end

describe Bundler::SharedHelpers do
  describe "#default_gemfile" do
    subject { Bundler::SharedHelpers.default_gemfile }
    before do
      ENV["BUNDLE_GEMFILE"] = "/path/Gemfile"
    end
    context "Gemfile is present" do
      it "returns the Gemfile path" do
        expected_gemfile_path = Pathname.new("/path/Gemfile")
        expect(subject).to eq(expected_gemfile_path)
      end
    end
    context "Gemfile is not present" do
      before do
        ENV["BUNDLE_GEMFILE"] = nil
      end
      it "raises a GemfileNotFound error" do
        expect { subject }.to raise_error(Bundler::GemfileNotFound, "Could not locate Gemfile")
      end
    end
  end
  describe "#const_get_safely" do
    context "when the namespace does have the requested constant" do
      subject { Bundler::SharedHelpers.const_get_safely(:VALID_CONSTANT, TargetNamespace) }
      it "returns the value of the requested constant" do
        expect(subject).to eq(1)
      end
    end
    context "when the requested constant is passed as a string" do
      subject { Bundler::SharedHelpers.const_get_safely("VALID_CONSTANT", TargetNamespace) }
      it "returns the value of the requested constant" do
        expect(subject).to eq(1)
      end
    end
    context "when the namespace does not have the requested constant" do
      subject { Bundler::SharedHelpers.const_get_safely("INVALID_CONSTANT", TargetNamespace) }
      it "returns nil" do
        expect(subject).to eq(nil)
      end
    end
  end
end
