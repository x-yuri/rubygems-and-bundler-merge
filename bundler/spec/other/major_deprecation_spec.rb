# frozen_string_literal: true

RSpec.describe "major deprecations" do
  let(:warnings) { err }

  describe "Bundler" do
    before do
      create_file "gems.rb", <<-G
        source "file:#{gem_repo1}"
        ruby #{RUBY_VERSION.dump}
        gem "rack"
      G
      bundle! "install"
    end

    describe ".clean_env" do
      it "is deprecated in favor of .unbundled_env" do
        source = "Bundler.clean_env"
        bundle "exec ruby -e #{source.dump}"
        expect(warnings).to have_major_deprecation \
          "`Bundler.clean_env` has been deprecated in favor of `Bundler.unbundled_env`. " \
          "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env`"
      end
    end

    describe ".environment" do
      it "is deprecated in favor of .load" do
        source = "Bundler.environment"
        bundle "exec ruby -e #{source.dump}"
        expect(warnings).to have_major_deprecation "Bundler.environment has been removed in favor of Bundler.load"
      end
    end

    describe "bundle update --quiet" do
      it "does not print any deprecations" do
        bundle :update, :quiet => true
        expect(warnings).not_to have_major_deprecation
      end
    end

    describe "bundle update" do
      before do
        bundle! "install"
      end

      it "does not warn when no options are given", :bundler => "< 2" do
        bundle! "update"
        expect(warnings).not_to have_major_deprecation
      end

      it "warns when no options are given", :bundler => "2" do
        bundle! "update"
        expect(warnings).to have_major_deprecation a_string_including("Pass --all to `bundle update` to update everything")
      end

      it "does not warn when --all is passed" do
        bundle! "update --all"
        expect(warnings).not_to have_major_deprecation
      end
    end

    describe "bundle install --binstubs" do
      xit "should output a deprecation warning" do
        bundle :install, :binstubs => true
        expect(warnings).to have_major_deprecation a_string_including("The --binstubs option will be removed")
      end
    end
  end

  context "when bundle install is run" do
    it "should not warn about gems.rb" do
      create_file "gems.rb", <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install
      expect(warnings).not_to have_major_deprecation
    end

    it "should print a proper warning when both gems.rb and Gemfile present, and use Gemfile", :bundler => "< 2" do
      create_file "gems.rb"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. The gems.rb and gems.rb.locked files are currently ignored, but they will get used as soon as you delete your Gemfile and Gemfile.lock files."
      )

      expect(the_bundle).to include_gem "rack 1.0"
    end

    it "should print a proper warning when both gems.rb and Gemfile present, and use gems.rb", :bundler => "2" do
      create_file "gems.rb"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
      )

      expect(the_bundle).not_to include_gem "rack 1.0"
    end

    context "with flags" do
      before do
        install_gemfile <<-G, :path => "vendor/bundle"
          source "file://#{gem_repo1}"
          gem "rack"
        G
      end

      it "should print a deprecation warning about autoremembering flags", :bundler => "3" do
        expect(warnings).to have_major_deprecation a_string_including(
          "flags passed to commands will no longer be automatically remembered."
        )
      end

      {
        :clean => true,
        :deployment => true,
        :frozen => true,
        :"no-cache" => true,
        :"no-prune" => true,
        :path => "vendor/bundle",
        :shebang => "ruby27",
        :system => true,
        :without => "development",
        :with => "development",
      }.each do |name, value|
        flag_name = "--#{name}"

        context "with the #{flag_name} flag", :bundler => "2" do
          it "should print a deprecation warning" do
            bundle "install #{flag_name} #{value}"

            expect(warnings).to have_major_deprecation(
              "The `#{flag_name}` flag is deprecated because it relied on " \
              "being remembered accross bundler invokations, which bundler " \
              "will no longer do in future versions. Instead please use " \
              "`bundle config #{name} '#{value}'`, and stop using this flag"
            )
          end
        end

        context "with the #{flag_name} flag", :bundler => "< 2" do
          it "should not print a deprecation warning" do
            bundle "install #{flag_name} #{value}"

            expect(warnings).not_to have_major_deprecation
          end
        end
      end
    end
  end

  context "when Bundler.setup is run in a ruby script" do
    before do
      create_file "gems.rb"
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack", :group => :test
      G

      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        require 'bundler/vendored_thor'

        Bundler.ui = Bundler::UI::Shell.new
        Bundler.setup
        Bundler.setup
      RUBY
    end

    it "should print a single deprecation warning", :bundler => "< 2" do
      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. The gems.rb and gems.rb.locked files are currently ignored, but they will get used as soon as you delete your Gemfile and Gemfile.lock files."
      )
    end

    it "should print a single deprecation warning", :bundler => "2" do
      expect(warnings).to include(
        "Multiple gemfiles (gems.rb and Gemfile) detected. Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
      )
    end
  end

  context "when `bundler/deployment` is required in a ruby script" do
    it "should print a capistrano deprecation warning" do
      ruby(<<-RUBY)
        require 'bundler/deployment'
      RUBY

      expect(warnings).to have_major_deprecation("Bundler no longer integrates " \
                             "with Capistrano, but Capistrano provides " \
                             "its own integration with Bundler via the " \
                             "capistrano-bundler gem. Use it instead.")
    end
  end

  describe Bundler::Dsl do
    let(:msg) do
      <<-EOS
The :github git source is deprecated, and will be removed in the future. Change any "reponame" :github sources to "username/reponame". Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:github) {|repo_name| "https://github.com/\#{repo_name}.git" }

      EOS
    end

    before do
      @rubygems = double("rubygems")
      allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
    end

    context "with github gems" do
      it "warns about the https change if people are opting out" do
        Bundler.settings.temporary "github.https" => false
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(2, "Setting `github.https` to false is deprecated and won't be supported in the future.")
        subject.gem("sparks", :github => "indirect/sparks")
      end

      it "upgrades to https by default", :bundler => "2" do
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "upgrades to https on request", :bundler => "< 2" do
        Bundler.settings.temporary "github.https" => true
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("sparks", :github => "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end
    end

    context "with bitbucket gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = <<-EOS
The :bitbucket git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:bitbucket) do |repo_name|
      user_name, repo_name = repo_name.split("/")
      repo_name ||= user_name
      "https://\#{user_name}@bitbucket.org/\#{user_name}/\#{repo_name}.git"
    end

        EOS
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("not-really-a-gem", :bitbucket => "mcorp/flatlab-rails")
      end
    end

    context "with gist gems" do
      it "warns about removal" do
        allow(Bundler.ui).to receive(:deprecate)
        msg = <<-EOS
The :gist git source is deprecated, and will be removed in the future. Add this code to the top of your Gemfile to ensure it continues to work:

    git_source(:gist) {|repo_name| "https://gist.github.com/\#{repo_name}.git" }

        EOS
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(3, msg)
        subject.gem("not-really-a-gem", :gist => "1234")
      end
    end
  end

  context "bundle show" do
    before do
      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle! :show
    end

    it "does not print a deprecation warning", :bundler => "< 2" do
      expect(warnings).not_to have_major_deprecation
    end

    it "prints a deprecation warning", :bundler => "2" do
      expect(warnings).to have_major_deprecation a_string_including("use `bundle list` instead of `bundle show`")
    end
  end

  context "bundle console" do
    before do
      bundle "console"
    end

    it "does not print a deprecation warning", :bundler => "< 2" do
      expect(warnings).not_to have_major_deprecation
    end

    it "prints a deprecation warning", :bundler => "2" do
      expect(warnings).to have_major_deprecation \
        a_string_including("bundle console will be replaced by `bin/console` generated by `bundle gem <name>`")
    end
  end
end
