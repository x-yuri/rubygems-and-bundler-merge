require "spec_helper"

describe "bundle cache with multiple platforms" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"

      platforms :mri, :rbx do
        gem "rack", "1.0.0"
      end

      platforms :jruby do
        gem "activesupport", "2.3.5"
      end
    G

    lockfile <<-G
      GEM
        remote: file:#{gem_repo1}/
        specs:
          rack (1.0.0)
          activesupport (2.3.5)

      PLATFORMS
        ruby
        java

      DEPENDENCIES
        rack (1.0.0)
        activesupport (2.3.5)
    G

    cache_gems "rack-1.0.0", "activesupport-2.3.5"
  end

  it "ensures that a succesful bundle install does not delete gems for other platforms" do
    bundle "install", :exitstatus => true

    expect(exitstatus).to eq 0

    expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    expect(bundled_app("vendor/cache/activesupport-2.3.5.gem")).to exist
  end

  it "ensures that a succesful bundle update does not delete gems for other platforms" do
    bundle "update", :exitstatus => true

    expect(exitstatus).to eq 0

    expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    expect(bundled_app("vendor/cache/activesupport-2.3.5.gem")).to exist
  end
end
