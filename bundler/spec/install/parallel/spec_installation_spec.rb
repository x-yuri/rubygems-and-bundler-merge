require "spec_helper"
require "bundler/installer/parallel_installer"

describe ParallelInstaller::SpecInstallation do
  let!(:dep) do
    a_spec = Object.new
    def a_spec.name
      "I like tests"
    end
    a_spec
  end

  describe "#ready_to_enqueue?" do
    context "when in enqueued state" do
      it "is falsey" do
        spec = ParallelInstaller::SpecInstallation.new(dep)
        spec.state = :enqueued
        expect(spec.ready_to_enqueue?).to be_falsey
      end
    end

    context "when in installed state" do
      it "returns falsey" do
        spec = ParallelInstaller::SpecInstallation.new(dep)
        spec.state = :installed
        expect(spec.ready_to_enqueue?).to be_falsey
      end
    end

    it "returns truthy" do
      spec = ParallelInstaller::SpecInstallation.new(dep)
      expect(spec.ready_to_enqueue?).to be_truthy
    end
  end

  describe "#dependencies_installed?" do
    context "when all dependencies are installed" do
      it "returns true" do
        dependencies = []
        dependencies << instance_double("SpecInstallation", :spec => "alpha", :name => "alpha", :installed? => true, :all_dependencies => [], :type => :production)
        dependencies << instance_double("SpecInstallation", :spec => "beta", :name => "beta", :installed? => true, :all_dependencies => [], :type => :production)
        all_specs = dependencies + [instance_double("SpecInstallation", :spec => "gamma", :name => "gamma", :installed? => false, :all_dependencies => [], :type => :production)]
        spec = ParallelInstaller::SpecInstallation.new(dep)
        allow(spec).to receive(:all_dependencies).and_return(dependencies)
        expect(spec.dependencies_installed?(all_specs)).to be_truthy
      end
    end

    context "when all dependencies are not installed" do
      it "returns false" do
        dependencies = []
        dependencies << instance_double("SpecInstallation", :spec => "alpha", :name => "alpha", :installed? => false, :all_dependencies => [], :type => :production)
        dependencies << instance_double("SpecInstallation", :spec => "beta", :name => "beta", :installed? => true, :all_dependencies => [], :type => :production)
        all_specs = dependencies + [instance_double("SpecInstallation", :spec => "gamma", :name => "gamma", :installed? => false, :all_dependencies => [], :type => :production)]
        spec = ParallelInstaller::SpecInstallation.new(dep)
        allow(spec).to receive(:all_dependencies).and_return(dependencies)
        expect(spec.dependencies_installed?(all_specs)).to be_falsey
      end
    end

    context "when dependencies that are not on the overall installation list are the only ones not installed" do
      it "raises an error" do
        dependencies = []
        dependencies << instance_double("SpecInstallation", :spec => "alpha", :name => "alpha", :installed? => true, :all_dependencies => [], :type => :production)
        all_specs = dependencies + [instance_double("SpecInstallation", :spec => "gamma", :name => "gamma", :installed? => false, :all_dependencies => [], :type => :production)]
        # Add dependency which is not in all_specs
        dependencies << instance_double("SpecInstallation", :spec => "beta", :name => "beta", :installed? => false, :all_dependencies => [], :type => :production)
        dependencies << instance_double("SpecInstallation", :spec => "delta", :name => "delta", :installed? => false, :all_dependencies => [], :type => :production)
        spec = ParallelInstaller::SpecInstallation.new(dep)
        allow(spec).to receive(:all_dependencies).and_return(dependencies)
        expect { spec.dependencies_installed?(all_specs) }.
          to raise_error(Bundler::LockfileError, /Your Gemfile.lock is corrupt\. The following.*'beta' 'delta'/)
      end
    end
  end
end
