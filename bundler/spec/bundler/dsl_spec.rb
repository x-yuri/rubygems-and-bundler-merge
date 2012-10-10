require 'spec_helper'

describe Bundler::Dsl do
  before do
    @rubygems = mock("rubygems")
    Bundler::Source::Rubygems.stub(:new){ @rubygems }
  end

  describe '#_normalize_options' do
    it "should convert :github to :git" do
      subject.gem("sparks", :github => "indirect/sparks")
      github_uri = "git://github.com/indirect/sparks.git"
      expect(subject.dependencies.first.source.uri).to eq(github_uri)
    end

    it "should convert 'rails' to 'rails/rails'" do
      subject.gem("rails", :github => "rails")
      github_uri = "git://github.com/rails/rails.git"
      expect(subject.dependencies.first.source.uri).to eq(github_uri)
    end

    it "should interpret slashless 'github:' value as account name" do
      subject.gem("bundler", :github => "carlhuda")
      github_uri = "git://github.com/carlhuda/bundler.git"
      expect(subject.dependencies.first.source.uri).to eq(github_uri)
    end

  end

  describe '#method_missing' do
    it 'should raise an error for unknown DSL methods' do
      Bundler.should_receive(:read_file).with("Gemfile").and_return("unknown")
      error_msg = "Undefined local variable or method `unknown'" \
        " for Gemfile\\s+from Gemfile:1"
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, Regexp.new(error_msg))
    end
  end

  describe "#eval_gemfile" do
    it "handles syntax errors with a useful message" do
      Bundler.should_receive(:read_file).with("Gemfile").and_return("}")
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /Gemfile syntax error/)
    end
  end

  describe "syntax errors" do
    it "should raise a Bundler::GemfileError" do
      gemfile "gem 'foo', :path => /unquoted/string/syntax/error"
      expect { Bundler::Dsl.evaluate(bundled_app("Gemfile"), nil, true) }.
        to raise_error(Bundler::GemfileError)
    end
  end
end
