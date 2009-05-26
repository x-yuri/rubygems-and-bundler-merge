require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Thor::Task do
  def task(options={})
    options.each do |key, value|
      options[key] = Thor::Option.parse(key, value)
    end

    @task ||= Thor::Task.new(:task, "I can has cheezburger", "can_has", options)
  end

  describe "#formatted_usage" do
    it "shows usage with options" do
      task('foo' => true, :bar => :required).formatted_usage.must == "can_has [--foo] --bar=BAR"
    end

    it "includes class options if a class is given" do
      klass = mock!.default_options{{ :bar => Thor::Option.parse(:bar, :required) }}.subject
      task('foo' => true).formatted_usage(klass, false).must == "can_has [--foo] --bar=BAR"
    end

    it "includes namespace"
    
  end
  
  it "runs a task"
end
