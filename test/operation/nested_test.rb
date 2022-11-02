require 'test_helper'

class NestedTest < Minitest::Spec
  DatabaseError = Class.new(Trailblazer::Activity::Signal)

  def trace(activity, ctx)
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])
    return Trailblazer::Developer::Trace::Present.(stack, node_options: {stack.to_a[0]=>{label: "TOP"}}).gsub(/:\d+/, ""), signal, ctx
  end

  module ComputeNested
    module_function

    def compute_nested(ctx, what:, **)
      what
    end
  end

  class SignUp < Trailblazer::Operation
    def self.b(ctx, **)
      ctx[:seq] << :b
      return DatabaseError if ctx[:b] == false

      true
    end

    step method(:b), Output(DatabaseError, :db_error) => End(:db_error)
  end

  class SignIn < Trailblazer::Operation
    include T.def_steps(:c)
    step :c
  end

  it "allows connection with custom output of a nested activity" do
    create = Class.new(Trailblazer::Operation) do
      include T.def_steps(:a, :d)

      step :a
      step Nested(SignUp), Output(:db_error) => Track(:no_user)
      step :d, magnetic_to: :no_user
    end

    result = create.(seq: [])
    result.inspect(:seq).must_equal %{<Result:true [[:a, :b, :d]] >}
    result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
  end

  it "allows connecting dynamically nested activities with custom output when auto wired" do
    create = Class.new(Trailblazer::Activity::FastTrack) do
      include ComputeNested
      include T.def_steps(:a, :d)

      step :a
      step Nested(:compute_nested, auto_wire: [SignUp, SignIn]),
        Output(:db_error) => Track(:no_user)
      step :d, magnetic_to: :no_user
    end

    #@ SignUp with {success}
    assert_invoke create, seq: %{[:a, :b]}, what: SignUp
    #@ SignUp with {db_error}, we go through d and then success
    assert_invoke create, seq: %{[:a, :b, :d]}, what: SignUp, b: false
    #@ SignIn, success
    assert_invoke create, seq: %{[:a, :c]}, what: SignIn
    #@ SignIn, failure is wired to Create:End.failure
    assert_invoke create, seq: %{[:a, :c]}, what: SignIn, c: false, terminus: :failure
  end

  it "raises RuntimeError if dynamically nested activities with custom output are not auto wired" do
    exception = assert_raises RuntimeError do
      Class.new(Trailblazer::Operation) do
        def compute_nested(ctx, what:, **)
          what
        end

        step Nested(:compute_nested), Output(:db_error) => Track(:no_user)
      end
    end

    exception.inspect.must_match 'No `db_error` output found'
  end


end

# TODO:  find_path in Nested
