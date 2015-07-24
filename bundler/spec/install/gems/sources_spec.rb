require "spec_helper"

describe "bundle install with gems on multiple sources" do
  # repo1 is built automatically before all of the specs run
  # it contains rack-obama 1.0.0 and rack 0.9.1 & 1.0.0 amongst other gems

  context "without source affinity" do
    before do
      # Oh no! Someone evil is trying to hijack rack :(
      # need this to be broken to check for correct source ordering
      build_repo gem_repo3 do
        build_gem "rack", repo3_rack_version do |s|
          s.write "lib/rack.rb", "RACK = 'FAIL'"
        end
      end
    end

    context "with multiple toplevel sources" do
      let(:repo3_rack_version) { "1.0.0" }

      before do
        gemfile <<-G
          source "file://#{gem_repo3}"
          source "file://#{gem_repo1}"
          gem "rack-obama"
          gem "rack"
        G
      end

      it "warns about ambiguous gems, but installs anyway, prioritizing sources last to first" do
        bundle :install

        expect(out).to include("Warning: this Gemfile contains multiple primary sources.")
        expect(out).to include("Warning: the gem 'rack' was found in multiple sources.")
        expect(out).to include("Installed from: file:#{gem_repo1}")
        should_be_installed("rack-obama 1.0.0", "rack 1.0.0")
      end

      it "errors when disable_multisource is set" do
        bundle "config disable_multisource true"
        bundle :install
        expect(out).to include("Each source after the first must include a block")
        expect(exitstatus).to eq(14) if exitstatus
      end
    end

    context "when different versions of the same gem are in multiple sources" do
      let(:repo3_rack_version) { "1.2" }

      before do
        gemfile <<-G
          source "file://#{gem_repo3}"
          source "file://#{gem_repo1}"
          gem "rack-obama"
          gem "rack", "1.0.0" # force it to install the working version in repo1
        G
      end

      it "warns about ambiguous gems, but installs anyway" do
        bundle :install

        expect(out).to include("Warning: this Gemfile contains multiple primary sources.")
        expect(out).to include("Warning: the gem 'rack' was found in multiple sources.")
        expect(out).to include("Installed from: file:#{gem_repo1}")
        should_be_installed("rack-obama 1.0.0", "rack 1.0.0")
      end
    end
  end

  context "with source affinity" do
    context "with sources given by a block" do
      before do
        # Oh no! Someone evil is trying to hijack rack :(
        # need this to be broken to check for correct source ordering
        build_repo gem_repo3 do
          build_gem "rack", "1.0.0" do |s|
            s.write "lib/rack.rb", "RACK = 'FAIL'"
          end
        end

        gemfile <<-G
          source "file://#{gem_repo3}"
          source "file://#{gem_repo1}" do
            gem "thin" # comes first to test name sorting
            gem "rack"
          end
          gem "rack-obama" # shoud come from repo3!
        G
      end

      it "installs the gems without any warning" do
        bundle :install
        expect(out).not_to include("Warning")
        should_be_installed("rack-obama 1.0.0", "rack 1.0.0")
      end

      it "can cache and deploy" do
        bundle :package

        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
        expect(bundled_app("vendor/cache/rack-obama-1.0.gem")).to exist

        bundle "install --deployment"

        expect(exitstatus).to eq(0) if exitstatus
        should_be_installed("rack-obama 1.0.0", "rack 1.0.0")
      end
    end

    context "with sources set by an option" do
      before do
        # Oh no! Someone evil is trying to hijack rack :(
        # need this to be broken to check for correct source ordering
        build_repo gem_repo3 do
          build_gem "rack", "1.0.0" do |s|
            s.write "lib/rack.rb", "RACK = 'FAIL'"
          end
        end

        gemfile <<-G
          source "file://#{gem_repo3}"
          gem "rack-obama" # should come from repo3!
          gem "rack", :source => "file://#{gem_repo1}"
        G
      end

      it "installs the gems without any warning" do
        bundle :install
        expect(out).not_to include("Warning")
        should_be_installed("rack-obama 1.0.0", "rack 1.0.0")
      end
    end

    context "with an indirect dependency" do
      before do
        build_repo gem_repo3 do
          build_gem "depends_on_rack", "1.0.1" do |s|
            s.add_dependency "rack"
          end
        end
      end

      context "when the indirect dependency is in the pinned source" do
        before do
          # we need a working rack gem in repo3
          update_repo gem_repo3 do
            build_gem "rack", "1.0.0"
          end

          gemfile <<-G
            source "file://#{gem_repo2}"
            source "file://#{gem_repo3}" do
              gem "depends_on_rack"
            end
          G
        end

        context "and not in any other sources" do
          before do
            build_repo(gem_repo2) {}
          end

          it "installs from the same source without any warning" do
            bundle :install
            expect(out).not_to include("Warning")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end

        context "and in another source" do
          before do
            # need this to be broken to check for correct source ordering
            build_repo gem_repo2 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end
          end

          it "installs from the same source without any warning" do
            bundle :install
            expect(out).not_to include("Warning")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end
      end

      context "when the indirect dependency is in a different source" do
        before do
          # In these tests, we need a working rack gem in repo2 and not repo3
          build_repo gem_repo2 do
            build_gem "rack", "1.0.0"
          end
        end

        context "and not in any other sources" do
          before do
            gemfile <<-G
              source "file://#{gem_repo2}"
              source "file://#{gem_repo3}" do
                gem "depends_on_rack"
              end
            G
          end

          it "installs from the other source without any warning" do
            bundle :install
            expect(out).not_to include("Warning")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end

        context "and in yet another source" do
          before do
            gemfile <<-G
              source "file://#{gem_repo1}"
              source "file://#{gem_repo2}"
              source "file://#{gem_repo3}" do
                gem "depends_on_rack"
              end
            G
          end

          it "installs from the other source and warns about ambiguous gems" do
            bundle :install
            expect(out).to include("Warning: this Gemfile contains multiple primary sources.")
            expect(out).to include("Warning: the gem 'rack' was found in multiple sources.")
            expect(out).to include("Installed from: file:#{gem_repo2}")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end

        context "and only the dependency is pinned" do
          before do
            # need this to be broken to check for correct source ordering
            build_repo gem_repo2 do
              build_gem "rack", "1.0.0" do |s|
                s.write "lib/rack.rb", "RACK = 'FAIL'"
              end
            end

            gemfile <<-G
              source "file://#{gem_repo3}" # contains depends_on_rack
              source "file://#{gem_repo2}" # contains broken rack

              gem "depends_on_rack" # installed from gem_repo3
              gem "rack", :source => "file://#{gem_repo1}"
            G
          end

          it "installs the dependency from the pinned source without warning" do
            bundle :install

            expect(out).not_to include("Warning: the gem 'rack' was found in multiple sources.")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")

            # In https://github.com/bundler/bundler/issues/3585 this failed
            # when there is already a lock file, and the gems are missing, so try again
            system_gems []
            bundle :install

            expect(out).not_to include("Warning: the gem 'rack' was found in multiple sources.")
            should_be_installed("depends_on_rack 1.0.1", "rack 1.0.0")
          end
        end
      end
    end

    context "with a gem that is only found in the wrong source" do
      before do
        build_repo gem_repo3 do
          build_gem "not_in_repo1", "1.0.0"
        end

        gemfile <<-G
          source "file://#{gem_repo3}"
          gem "not_in_repo1", :source => "file://#{gem_repo1}"
        G
      end

      it "does not install the gem" do
        bundle :install
        expect(out).to include("Could not find gem 'not_in_repo1'")
      end
    end

    context "with an existing lockfile" do
      before do
        system_gems "rack-0.9.1", "rack-1.0.0"

        lockfile <<-L
          GEM
            remote: file:#{gem_repo1}
            remote: file:#{gem_repo3}
            specs:
              rack (0.9.1)

          PLATFORMS
            ruby

          DEPENDENCIES
            rack!
        L

        gemfile <<-G
          source "file://#{gem_repo1}"
          source "file://#{gem_repo3}" do
            gem 'rack'
          end
        G
      end

      # Reproduction of https://github.com/bundler/bundler/issues/3298
      it "does not unlock the installed gem on exec" do
        should_be_installed("rack 0.9.1")
      end
    end

    context "with a path gem in the same Gemfile" do
      before do
        build_lib "foo"

        gemfile <<-G
          gem "rack", :source => "file://#{gem_repo1}"
          gem "foo", :path => "#{lib_path("foo-1.0")}"
        G
      end

      it "does not unlock the non-path gem after install" do
        bundle :install

        bundle %{exec ruby -e 'puts "OK"'}

        expect(out).to include("OK")
        expect(exitstatus).to eq(0) if exitstatus
      end
    end
  end

  context "when an older version of the same gem also ships with Ruby" do
    before do
      system_gems "rack-0.9.1"

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack" # shoud come from repo1!
      G
    end

    it "installs the gems without any warning" do
      bundle :install
      expect(out).not_to include("Warning")
      should_be_installed("rack 1.0.0")
    end
  end

  context "when a single source contains multiple locked gems" do
    before do
      # 1. With these gems,
      build_repo4 do
        build_gem "foo", "0.1"
        build_gem "bar", "0.1"
      end

      # 2. Installing this gemfile will produce...
      gemfile <<-G
        source 'file://#{gem_repo1}'
        gem 'rack'
        gem 'foo', '~> 0.1', :source => 'file://#{gem_repo4}'
        gem 'bar', '~> 0.1', :source => 'file://#{gem_repo4}'
      G

      # 3. this lockfile.
      lockfile <<-L
        GEM
          remote: file:/Users/andre/src/bundler/bundler/tmp/gems/remote1/
          remote: file:/Users/andre/src/bundler/bundler/tmp/gems/remote4/
          specs:
            bar (0.1)
            foo (0.1)
            rack (1.0.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          bar (~> 0.1)!
          foo (~> 0.1)!
          rack
      L

      bundle "install --path ../gems/system"

      # 4. Then we add some new versions...
      update_repo4 do
        build_gem "foo", "0.2"
        build_gem "bar", "0.3"
      end
    end

    it "allows them to be unlocked separately" do
      # 5. and install this gemfile, updating only foo.
      install_gemfile <<-G
        source 'file://#{gem_repo1}'
        gem 'rack'
        gem 'foo', '~> 0.2', :source => 'file://#{gem_repo4}'
        gem 'bar', '~> 0.1', :source => 'file://#{gem_repo4}'
      G

      # 6. Which should update foo to 0.2, but not the (locked) bar 0.1
      should_be_installed("foo 0.2")
      should_be_installed("bar 0.1")
    end
  end
end
