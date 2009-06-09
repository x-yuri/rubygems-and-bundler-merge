require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Thor::Util do
  describe "#full_const_get" do
    it "looks for a constant in the given object" do
      Thor::Util.full_const_get(Object, :Thor).must == Thor
    end

    it "does not looks for constants in the ancestors chain" do
      lambda {
        Thor::Util.full_const_get(Thor::Util, :Thor)
      }.must raise_error(NameError)

      lambda {
        Thor::Util.const_get(:Thor)
      }.must_not raise_error
    end

    it "ignores :: in the look up" do
      Thor::Util.full_const_get(Thor, :"::Util").must == Thor::Util
    end
  end

  describe "#make_constant" do
    it "returns the constant given by the string" do
      Thor::Util.make_constant("Object").must == Object
    end

    it "resolves constant nesting" do
      Thor::Util.make_constant("Thor::Util").must == Thor::Util
    end

    it "raises an error if the constant cannot be found in the given base" do
      lambda {
        Thor::Util.make_constant("Foo", [])
      }.must raise_error(NameError)
    end
  end

  describe "#namespace_to_constant_name" do
    it "returns 'Default' if no name is given" do
      Thor::Util.namespace_to_constant_name("").must == "Default"
    end

    it "upcases the namespaces" do
      Thor::Util.namespace_to_constant_name("foo").must == "Foo"
      Thor::Util.namespace_to_constant_name("foo:bar").must == "Foo::Bar"
    end

    it "expands task namespacing into constant nesting" do
      Thor::Util.namespace_to_constant_name("foo:bar:baz").must == "Foo::Bar::Baz"
    end

    it "replaces snake-casing with camel-casing" do
      Thor::Util.namespace_to_constant_name("foo_bar:bar_baz").must == "FooBar::BarBaz"
    end
  end

  describe "#namespace_to_constant" do
    it "returns the named constant" do
      Thor::Util.namespace_to_constant('thor:core_ext:ordered_hash').must == Thor::CoreExt::OrderedHash
    end

    it "raises a Thor::Error if the namespace is not available" do
      lambda {
        Thor::Util.namespace_to_constant('foo:bar')
      }.must raise_error(Thor::Error)
    end
  end

  describe "#constant_to_namespace" do
    it "replaces constant nesting with task namespacing" do
      Thor::Util.constant_to_namespace("Foo::Bar::Baz").must == "foo:bar:baz"
    end

    it "snake-cases component strings" do
      Thor::Util.constant_to_namespace("FooBar::BarBaz::BazBoom").must == "foo_bar:bar_baz:baz_boom"
    end

    it "gets rid of an initial Default module" do
      Thor::Util.constant_to_namespace("Default::Foo::Bar").must == ":foo:bar"
      Thor::Util.constant_to_namespace("Default").must == ""
    end

    it "accepts class and module objects" do
      Thor::Util.constant_to_namespace(Thor::CoreExt::OrderedHash).must == "thor:core_ext:ordered_hash"
      Thor::Util.constant_to_namespace(Thor::Util).must == "thor:util"
    end

    it "removes Thor::Sandbox namespace" do
      Thor::Util.constant_to_namespace("Thor::Sandbox::Package").must == "package"
    end
  end

  describe "#namespaces_in_contents" do
    it "returns an array of names of constants defined in the string" do
      list = Thor::Util.namespaces_in_contents("class Foo; class Bar < Thor; end; end; class Baz; class Bat; end; end")
      list.must include("foo:bar")
      list.must_not include("bar:bat")
    end

    it "doesn't put the newly-defined constants in the enclosing namespace" do
      Thor::Util.namespaces_in_contents("class Blat; end")
      defined?(Blat).must_not be
      defined?(Thor::Sandbox::Blat).must be
    end
  end

  describe "#snake_case" do
    it "preserves no-cap strings" do
      Thor::Util.snake_case("foo").must == "foo"
      Thor::Util.snake_case("foo_bar").must == "foo_bar"
    end

    it "downcases all-caps strings" do
      Thor::Util.snake_case("FOO").must == "foo"
      Thor::Util.snake_case("FOO_BAR").must == "foo_bar"
    end

    it "downcases initial-cap strings" do
      Thor::Util.snake_case("Foo").must == "foo"
    end

    it "replaces camel-casing with underscores" do
      Thor::Util.snake_case("FooBarBaz").must == "foo_bar_baz"
      Thor::Util.snake_case("Foo_BarBaz").must == "foo_bar_baz"
    end

    it "places underscores between multiple capitals" do
      Thor::Util.snake_case("ABClass").must == "a_b_class"
    end
  end

  describe "#namespace_to_thor_class" do
    it "returns a Thor::Group class if full namespace matches" do
      Thor::Util.namespace_to_thor_class("my_counter").must == [MyCounter, nil]
    end

    it "returns a Thor class if full namespace matches" do
      Thor::Util.namespace_to_thor_class("thor").must == [Thor, nil]
    end

    it "returns a Thor class and the task name" do
      Thor::Util.namespace_to_thor_class("thor:help").must == [Thor, "help"]
    end

    it "fallbacks in the namespace:task look up even if a full namespace does not match" do
      Thor.const_set(:Help, Module.new)
      Thor::Util.namespace_to_thor_class("thor:help").must == [Thor, "help"]
      Thor.send :remove_const, :Help
    end

    describe 'errors' do
      it "raises an error if the Thor class or task can't be found" do
        lambda {
          Thor::Util.namespace_to_thor_class("foobar")
        }.must raise_error(Thor::Error, "could not find Thor class or task 'foobar'")
      end

      it "raises an error if the task does not inherit from Thor" do
        lambda {
          Thor::Util.namespace_to_thor_class("object:help")
        }.must raise_error(Thor::Error, "'Object' is not a Thor class")
      end
    end
  end

  describe "#print_list" do
    it "does not print if the list is empty" do
      capture(:stdout){ Thor::Util.print_list([]) }.must be_empty
    end

    it "prints each item on the list" do
      list    = [ %w(a 1), %w(b 2), %w(c 3) ]
      content = capture(:stdout){ Thor::Util.print_list(list) }

      content.must =~ /^  a +# 1$/
      content.must =~ /^  b +# 2$/
      content.must =~ /^  c +# 3$/
    end

    it "does not show description if it's not available" do
      list    = [ %w(a 1), ["b", nil], %w(c 3) ]
      content = capture(:stdout){ Thor::Util.print_list(list) }
      content.must =~ /^  b +$/
    end

    it "skips spacing if required" do
      list    = [ %w(a 1), %w(b 2), %w(c 3) ]
      content = capture(:stdout){ Thor::Util.print_list(list, :skip_spacing => true) }

      content.must =~ /^a +# 1$/
      content.must =~ /^b +# 2$/
      content.must =~ /^c +# 3$/
    end
  end

  describe "#print_table" do
    it "prints each item on the table" do
      table   = [ %w(a 1), %w(b 2), %w(c 3) ]
      content = capture(:stdout){ Thor::Util.print_table(table) }

      content.must =~ /^a   1$/
      content.must =~ /^b   2$/
      content.must =~ /^c   3$/
    end

    it "calculates the maximum size from each item and use it as padding" do
      table    = [ %w(a 1), %w(foo 2), %w(c 3) ]
      content = capture(:stdout){ Thor::Util.print_table(table) }.split("\n")

      content[0].size.must == 7
      content[1].size.must == 7
      content[2].size.must == 7
    end
  end

  describe "#thor_root" do
    before(:each) do
      stub(ENV)[]
    end

    it "returns the user path if none variable is set on the environment" do
      Thor::Util.thor_root.must == "/home/jose"
    end

    it "returns the *unix system path if file cannot be expanded and separator does not exist" do
      stub(File).expand_path("~"){ raise }
      previous_value = File::ALT_SEPARATOR
      capture(:stderr){ File.const_set(:ALT_SEPARATOR, false) }
      Thor::Util.thor_root.must == "/"
      capture(:stderr){ File.const_set(:ALT_SEPARATOR, previous_value) }
    end

    it "returns the windows system path if file cannot be expanded and a separator exists" do
      stub(File).expand_path("~"){ raise }
      previous_value = File::ALT_SEPARATOR
      capture(:stderr){ File.const_set(:ALT_SEPARATOR, true) }
      Thor::Util.thor_root.must == "C:/"
      capture(:stderr){ File.const_set(:ALT_SEPARATOR, previous_value) }
    end

    it "returns HOME/.thor if set" do
      stub(ENV)["HOME"].returns{ "/home/user" }
      Thor::Util.thor_root.must == "/home/user/.thor"
    end

    it "returns path with HOMEDRIVE and HOMEPATH if set" do
      stub(ENV)["HOMEDRIVE"].returns{ "D:/" }
      stub(ENV)["HOMEPATH"].returns{ "Documents and Settings/James" }
      Thor::Util.thor_root.must == "D:/Documents and Settings/James/.thor"
    end

    it "returns APPDATA/.thor if set" do
      stub(ENV)["APPDATA"].returns{ "/home/user" }
      Thor::Util.thor_root.must == "/home/user/.thor"
    end
  end

  describe "#convert_constants_to_namespaces" do
    before(:each) do
      @hash = {
        :git => {
          :constants => [Object, "Thor::Sandbox::Package", Thor::CoreExt::OrderedHash]
        }
      }
    end

    it "converts constants in the hash to namespaces" do
      Thor::Util.convert_constants_to_namespaces(@hash)
      @hash[:git][:namespaces].must == [ "object", "package", "thor:core_ext:ordered_hash" ]
    end

    it "returns true if the hash changed" do
      Thor::Util.convert_constants_to_namespaces(@hash).must be_true
    end

    it "does not add namespaces to the hash if namespaces were already added" do
      Thor::Util.convert_constants_to_namespaces(@hash)
      Thor::Util.convert_constants_to_namespaces(@hash).must be_false
    end
  end
end
