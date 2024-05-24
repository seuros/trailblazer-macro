require "test_helper"
module Autogenerated
class DocsModelTest < Minitest::Spec
  Song = Struct.new(:id, :title) do
    def self.find_by(args)
      key, value = args.flatten
      return nil if value.nil?
      return new(value) if key == :id
      new(2, value) if key == :title
    end

    def self.[](id)
      id.nil? ? nil : new(id+99)
    end
  end

  #:op
  module Song::Operation
    class Create < Trailblazer::Operation
      step Model(Song, :new)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:op end

  #:update
  module Song::Operation
    class Update < Trailblazer::Operation
      step Model(Song, :find_by)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update end

  it "defaults {:params} to empty hash when not passed" do
    assert_invoke Song::Operation::Create, seq: "[:validate, :save]",
      expected_ctx_variables: {model: Song.new}

    assert_invoke Song::Operation::Update, seq: "[]",
      terminus: :failure
  end

  #~ctx_to_result
  it do
    #:create
    result = Song::Operation::Create.(params: {}, seq: [])
    puts result[:model] #=> #<struct Song id=nil, title=nil>
    #:create end

    assert_invoke Song::Operation::Create, params: {},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.new}
  end

  it do
    #:update-ok
    result = Song::Operation::Update.(params: {id: 1}, seq: [])
    result[:model] #=> #<Song id=1, ...>
    result.success? # => true
    #:update-ok end

    assert_equal result[:model].inspect, %{#<struct #{Song} id=1, title=nil>}
    assert_equal result.event.to_h[:semantic], :success
  end

  it do
    #:update-fail
    result = Song::Operation::Update.(params: {})
    result[:model] #=> nil
    result.success? # => false
    #:update-fail end


    assert_equal result[:model].inspect, %{nil}
    assert_equal result.event.to_h[:semantic], :failure
  end
  #~ctx_to_result end
end

class DocsModelFindByTitleTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  #:update-with-find-by-key
  module Song::Operation
    class Update < Trailblazer::Operation
      step Model(Song, :find_by, :title) # third positional argument.
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update-with-find-by-key end

  #~ctx_to_result
  it do
    #:update-with-find-by-key-ok
    result = Song::Operation::Update.(params: {title: "Test"}, seq: [])
    result[:model] #=> #<struct Song id=2, title="Test">
    #:update-with-find-by-key-ok end

    assert_equal result[:model].inspect, %{#<struct #{Song} id=2, title="Test">}
  end

  it do
    #:key-title-fail
    result = Song::Operation::Update.(params: {title: nil}, seq: [])

    assert_equal result[:model].inspect, %{nil}
    #:key-title-fail end
  end
  #~ctx_to_result end
end

class DocsModelAccessorTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  #:show
  module Song::Operation
    class Update < Trailblazer::Operation
      step Model(Song, :[])
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:show end

  #~ctx_to_result
  it do
    #:show-ok
    result = Song::Operation::Update.(params: {id: 1}, seq: [])
    result[:model] #=> #<struct Song id=1, title="Roxanne">
    #:show-ok end

    assert_equal result[:model].inspect, %{#<struct #{Song} id=100, title=nil>}
  end
  #~ctx_to_result end
end

class DocsModelDependencyInjectionTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  module Song::Operation
    class Create < Trailblazer::Operation
      step Model(Song, :new)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it "allows injecting {:model.class} and friends" do
    class Hit < Song
    end

    #:di-model-class
    result = Song::Operation::Create.(params: {}, :"model.class" => Hit, seq: [])
    #:di-model-class end

    assert_equal result[:model].inspect, %{#<struct #{Hit} id=nil, title=nil>}

  # inject all variables
    #:di-all
    result = Song::Operation::Create.(
      params:               {title: "Olympia"}, # some random variable.
      "model.class":        Hit,
      "model.action":       :find_by,
      "model.find_by_key":  :title, seq: []
    )
    #:di-all end

    assert_equal result[:model].inspect, %{#<struct #{Hit} id=2, title="Olympia">}
end

  # use empty Model() and inject {model.class} and {model.action}
class DocsModelEmptyDITest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  Hit  = Class.new(Song)

  #:op-model-empty
  module Song::Operation
    class Create < Trailblazer::Operation
      step Model()
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
    #:op-model-empty end
  end

  it do
    result = Song::Operation::Create.(params: {}, :"model.class" => Hit, seq: [])

    assert_equal result[:model].inspect, %{#<struct #{Hit} id=nil, title=nil>}
  end
end

class DocsModelIOTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  Hit  = Class.new(Song)

  it "allows to use composable I/O with macros" do
    #:in
    module Song::Operation
      class Create < Trailblazer::Operation
        step Model(Song, :find_by),
          In() => ->(ctx, my_id:, **) { ctx.merge(params: {id: my_id}) } # Model() needs {params[:id]}.
        # ...
      end
    end
    #:in end

    result = Song::Operation::Create.(params: {}, my_id: 1, :"model.class" => Hit)

    assert_equal result[:model].inspect, %{#<struct #{Hit} id=1, title=nil>}
=begin
#:in-call
result = Create.(my_id: 1)
#:in-call end
=end
  end
end
end

class Model404TerminusTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  #:update-with-not-found-end
  module Song::Operation
    class Update < Trailblazer::Operation
      step Model(Song, :find_by, not_found_terminus: true)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update-with-not-found-end end

  it do
    assert_invoke Song::Operation::Update, params: {id: 1},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.find_by(id: 1)}
    assert_invoke Song::Operation::Update, params: {id: nil}, terminus: :not_found

    #:not_found
    result = Song::Operation::Update.(params: {id: nil})
    result.success? # => false
    #:not_found end
  end
end
end