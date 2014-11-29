require 'spec_helper'

describe Bundler::Dsl do
  before do
    @rubygems = double("rubygems")
    allow(Bundler::Source::Rubygems).to receive(:new){ @rubygems }
  end

  describe "#git_source" do
    it "registers custom hosts" do
      subject.git_source(:example){ |repo_name| "git@git.example.com:#{repo_name}.git" }
      subject.git_source(:foobar){ |repo_name| "git@foobar.com:#{repo_name}.git" }
      subject.gem("dobry-pies", :example => "strzalek/dobry-pies")
      example_uri = "git@git.example.com:strzalek/dobry-pies.git"
      expect(subject.dependencies.first.source.uri).to eq(example_uri)
    end

    it "raises expection on invalid hostname" do
      expect {
        subject.git_source(:group){ |repo_name| "git@git.example.com:#{repo_name}.git" }
      }.to raise_error(Bundler::InvalidOption)
    end

    it "expects block passed" do
      expect{ subject.git_source(:example) }.to raise_error(Bundler::InvalidOption)
    end

    context "default hosts (git, gist)" do
      it "converts :github to :git" do
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "git://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts numeric :gist to :git" do
        subject.gem("not-really-a-gem", :gist => 2859988)
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :gist to :git" do
        subject.gem("not-really-a-gem", :gist => "2859988")
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts 'rails' to 'rails/rails'" do
        subject.gem("rails", :github => "rails")
        github_uri = "git://github.com/rails/rails.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :bitbucket to :git" do
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/flatlab-rails.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end

      it "converts 'mcorp' to 'mcorp/mcorp'" do
        subject.gem("not-really-a-gem", :bitbucket => "mcorp")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/mcorp.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end
    end
  end

  describe "#method_missing" do
    it "raises an error for unknown DSL methods" do
      expect(Bundler).to receive(:read_file).with("Gemfile").
        and_return("unknown")

      error_msg = "Undefined local variable or method `unknown'" \
        " for Gemfile\\s+from Gemfile:1"
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, Regexp.new(error_msg))
    end
  end

  describe "#eval_gemfile" do
    it "handles syntax errors with a useful message" do
      expect(Bundler).to receive(:read_file).with("Gemfile").and_return("}")
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /Gemfile syntax error/)
    end
  end

  describe "#gem" do
    [:ruby, :ruby_18, :ruby_19, :ruby_20, :ruby_21, :ruby_22, :mri, :mri_18, :mri_19,
     :mri_20, :mri_21, :jruby, :rbx].each do |platform|
      it "allows #{platform} as a valid platform" do
        subject.gem("foo", :platform => platform)
      end
    end

    it "rejects invalid platforms" do
      expect { subject.gem("foo", :platform => :bogus) }.
        to raise_error(Bundler::GemfileError, /is not a valid platform/)
    end

    it "rejects with a leading space in the name" do
      expect { subject.gem(" foo") }.
        to raise_error(Bundler::GemfileError, /' foo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a trailing space in the name" do
      expect { subject.gem("foo ") }.
        to raise_error(Bundler::GemfileError, /'foo ' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a space in the gem name" do
      expect { subject.gem("fo o") }.
        to raise_error(Bundler::GemfileError, /'fo o' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a tab in the gem name" do
      expect { subject.gem("fo\to") }.
        to raise_error(Bundler::GemfileError, /'fo\to' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a newline in the gem name" do
      expect { subject.gem("fo\no") }.
        to raise_error(Bundler::GemfileError, /'fo\no' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a carriage return in the gem name" do
      expect { subject.gem("fo\ro") }.
        to raise_error(Bundler::GemfileError, /'fo\ro' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a form feed in the gem name" do
      expect { subject.gem("fo\fo") }.
        to raise_error(Bundler::GemfileError, /'fo\fo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects symbols as gem name" do
      expect { subject.gem(:foo) }.
        to raise_error(Bundler::GemfileError, /You need to specify gem names as Strings. Use 'gem "foo"' instead/)
    end
  end

  context "can bundle groups of gems with" do
    # git "https://github.com/rails/rails.git" do
    #   gem "railties"
    #   gem "action_pack"
    #   gem "active_model"
    # end
    describe "#git" do
      it "from a single repo" do
        rails_gems = ["railties", "action_pack", "active_model"]
        example = subject.git "https://github.com/rails/rails.git" do
          rails_gems.each { |rails_gem| subject.send :gem, rails_gem }
        end
        expect(subject.dependencies.map(&:name)).to match_array rails_gems
      end
    end

    # github 'spree' do
    #   gem 'spree_core'
    #   gem 'spree_api'
    #   gem 'spree_backend'
    # end
    describe "#github" do
      it "from github" do
        spree_gems = ["spree_core", "spree_api", "spree_backend"]
        example = subject.github "spree" do
          spree_gems.each { |spree_gem| subject.send :gem, spree_gem }
        end
        expect(subject.dependencies.map(&:name)).to match_array spree_gems
      end
    end
  end

  describe "syntax errors" do
    it "will raise a Bundler::GemfileError" do
      gemfile "gem 'foo', :path => /unquoted/string/syntax/error"
      expect { Bundler::Dsl.evaluate(bundled_app("Gemfile"), nil, true) }.
        to raise_error(Bundler::GemfileError, /Gemfile syntax error/)
    end
  end
end
