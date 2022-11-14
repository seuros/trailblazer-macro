require "test_helper"


# step Macro::Each(:report_templates, key: :report_template) {
#   step Subprocess(ReportTemplate::Update), input: :input_report_template
#   fail :set_report_template_errors
# }

# def report_templates(ctx, **)      ctx["result.contract.default"].report_templates
# end

class EachTest < Minitest::Spec
  class Composer < Struct.new(:full_name, :email)
  end

#@ operation has {#composers_for_each}
  module B
    class Song < Struct.new(:id, :title, :band, :composers)
      def self.find_by(id:)
        if id == 2
          return Song.new(id, nil, nil, [Composer.new("Fat Mike", "mike@fat.wreck"), Composer.new("El Hefe")])
        end

        if id == 3
          return Song.new(id, nil, nil, [Composer.new("Fat Mike", "mike@fat.wreck"), Composer.new("El Hefe", "scammer@spam")])
        end

        Song.new(id, nil, nil, [Composer.new("Fat Mike"), Composer.new("El Hefe")])
      end
    end

    #:each
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        #:each-dataset
        step Each(dataset_from: :composers_for_each) {
          step :notify_composers
        }
        #:each-dataset end
        step :rearrange

        # "decider interface"
        #:dataset_from
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        #:dataset_from end

        #:iterated
        def notify_composers(ctx, index:, item:, **)
          ctx[:value] = [index, item.full_name]
        end
        #:iterated end
        #~meths
        def model(ctx, params:, **)
          ctx[:model] = Song.find_by(id: params[:id])
        end

        include T.def_steps(:rearrange)
        #~meths end
      end
    end
    #:each end
  end # B

  it "allows a dataset compute in the hosting activity" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke B::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      },
      seq: "[:rearrange]"

=begin
    ctx = {params: {id: 1}, seq: []} # Song 1 has two composers.
    #:collected_from_each
    ctx = {params: {id: 1}} # Song 1 has two composers.
    signal, (ctx, _) = Trailblazer::Activity::TaskWrap.invoke(B::Song::Activity::Cover, [ctx, {}])

    puts ctx[:collected_from_each] #=> [[0, "Fat Mike"], [1, "El Hefe"]]
    #:collected_from_each end
=end
  end

  module CoverMethods
    def notify_composers(ctx, index:, item:, **)
      ctx[:value] = [index, item.full_name]
    end

    def model(ctx, params:, **)
      ctx[:model] = EachTest::B::Song.find_by(id: params[:id])
    end

    include T.def_steps(:rearrange)
  end

#@ operation has dedicated step {#find_composers}
  module C
    class Song < B::Song; end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step :find_composers
        step Each() {
            step :notify_composers
        }, In() => {:composers => :dataset}
        step :rearrange

        def find_composers(ctx, model:, **)
          # You could also say {ctx[:dataset] = model.composers},
          # and wouldn't need the In() mapping.
          ctx[:composers] = model.composers
        end
        #~meths
        include CoverMethods
        #~meths end
      end
    end
  end # C

  it "dataset can come from the hosting activity" do
#@ {:dataset} is not part of the outgoing {ctx}.
  assert_invoke B::Song::Activity::Cover, params: {id: 1},
    expected_ctx_variables: {
      model: B::Song.find_by(id: 1),
      collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
    }, seq: "[:rearrange]"
  end

  it "dataset coming via In() from the operation" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke C::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: C::Song.find_by(id: 1),
        composers: [Composer.new("Fat Mike"), Composer.new("El Hefe")],
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      }, seq: "[:rearrange]"
  end

#@ {:item_key}
  module E
    class Song < B::Song; end

    #:composer
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        #~meths
        step :model
        #:item_key
        step Each(dataset_from: :composers_for_each, item_key: :composer) {
          step :notify_composers
        }
        #:item_key end
        step :rearrange


        # circuit-step interface! "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
        def notify_composers(ctx, composer:, **)
          ctx[:value] = composer.full_name
        end
      end
    end
    #:composer end
  end # E

  it "{item_key: :composer}" do
    assert_invoke E::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        collected_from_each: ["Fat Mike", "El Hefe"]
      },
      seq: "[:rearrange]"
  end

#@ failure in Each
  module F
    class Song < B::Song; end

    class Notify
      def self.send_email(email)
        return if email.nil?
        true
      end
    end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step Each(dataset_from: :composers_for_each) {
          step :notify_composers
        }
        step :rearrange

        def notify_composers(ctx, item:, **)
          if Notify.send_email(item.email)
            ctx[:value] = item.email # let's collect all emails that could be sent.
            return true
          else
            return false
          end
        end
        #~meths

        # circuit-step interface! "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
  end # F

  it "failure in Each" do
    assert_invoke F::Song::Activity::Cover, params: {id: 2},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 2),
        collected_from_each: ["mike@fat.wreck", nil],
      },
      seq: "[]",
      terminus: :failure

    Trailblazer::Developer.wtf?(F::Song::Activity::Cover, [{params: {id: 2}, seq: []}])
  end


#@ Each with operation
  module D
    class Song < B::Song; end

    #:operation-class
    module Song::Activity
      class Notify < Trailblazer::Activity::Railway
        step :send_email

        def send_email(ctx, index:, item:, **)
          ctx[:value] = [index, item.full_name]
        end
      end
    end
    #:operation-class end

    #:operation
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step Each(Notify, dataset_from: :composers_for_each)
        step :rearrange
        #~meths
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
    #:operation end
  end

  it "Each(Activity::Railway)" do
    assert_invoke D::Song::Activity::Cover, params: {id: 1},
      seq:                    "[:rearrange]",
      expected_ctx_variables: {
        model:                D::Song.find_by(id: 1),
        collected_from_each:  [[0, "Fat Mike"], [1, "El Hefe"],]
      }
  end

#@ Each with operation with three outcomes. Notify terminates on {End.spam_email},
#  which is then routed to End.spam_alert in the hosting activity.
# NOTE: this is not documented, yet.
  module G
    class Song < B::Song; end

    module Song::Activity
      class Notify < Trailblazer::Activity::Railway
        terminus :spam_email
        # SpamEmail = Class.new(Trailblazer::Activity::Signal)

        step :send_email, Output(:failure) => Track(:spam_email)

        def send_email(ctx, index:, item:, **)
          return false if item.email == "scammer@spam"
          ctx[:value] = [index, item.full_name]
        end
      end
    end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        terminus :spam_alert

        step :model
        step Each(Notify, dataset_from: :composers_for_each),
          Output(:spam_email) => Track(:spam_alert)
        step :rearrange
        #~meths
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
  end

  it "Each(Activity::Railway) with End.spam_email" do
    Trailblazer::Developer.wtf?(G::Song::Activity::Cover, [{params: {id: 3}}, {}])

    assert_invoke G::Song::Activity::Cover, params: {id: 3},
      terminus:                :spam_alert,
      seq:                    "[]",
      expected_ctx_variables: {
        model:                G::Song.find_by(id: 3),
        collected_from_each:  [[0, "Fat Mike"], nil,]
      }
  end
end


class DocsEachUnitTest < Minitest::Spec
  module ComputeItem
    def compute_item(ctx, item:, index:, **)
      ctx[:value] = "#{item}-#{index.inspect}"
    end
  end

  def self.block
    -> (*){
      step :compute_item
    }
  end

  it "with Trace" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a, :b)
      include ComputeItem

      step :a
      step Each(&DocsEachUnitTest.block), id: "Each/1"
      step :b
    end

    ctx = {seq: [], dataset: [3,2,1]}

    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])

    assert_equal Trailblazer::Developer::Trace::Present.(stack,
      node_options: {stack.to_a[0] => {label: "<a-Each-b>"}}), %{<a-Each-b>
|-- Start.default
|-- a
|-- Each/1
|   |-- Start.default
|   |-- Each.iterate.block
|   |   |-- invoke_block_activity.0
|   |   |   |-- Start.default
|   |   |   |-- compute_item
|   |   |   `-- End.success
|   |   |-- invoke_block_activity.1
|   |   |   |-- Start.default
|   |   |   |-- compute_item
|   |   |   `-- End.success
|   |   `-- invoke_block_activity.2
|   |       |-- Start.default
|   |       |-- compute_item
|   |       `-- End.success
|   `-- End.success
|-- b
`-- End.success}

  #@ compile time
  #@ make sure we can find tasks/compile-time artifacts in Each by using their {compile_id}.
    assert_equal Trailblazer::Developer::Introspect.find_path(activity,
      ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])[0].task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_item>}
    # puts Trailblazer::Developer::Render::TaskWrap.(activity, ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])

  # TODO: grab runtime ctx for iteration 134
  end

  it "Each::Circuit" do
    activity = Trailblazer::Macro.Each(&DocsEachUnitTest.block)[:task]

    my_exec_context = Class.new do
      include ComputeItem
    end.new

    ctx = {
      dataset: [1,2,3]
    }

    # signal, (_ctx, _) = Trailblazer::Activity::TaskWrap.invoke(activity, [ctx])
    signal, (_ctx, _) = Trailblazer::Developer.wtf?(activity, [ctx], exec_context: my_exec_context)
    assert_equal _ctx[:collected_from_each], ["1-0", "2-1", "3-2"]
  end


  it "accepts iterated {block}" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include ComputeItem

      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item
      }
    end

    Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "can see the entire ctx" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      def compute_item_with_current_user(ctx, item:, index:, current_user:, **)
        ctx[:value] = "#{item}-#{index.inspect}-#{current_user}"
      end

      step Each() { # expects {:dataset}
        step :compute_item_with_current_user
      }
    end

    Trailblazer::Developer.wtf?(
      activity,
      [{
          dataset:      ["one", "two", "three"],
          current_user: Object,
        },
      {}]
    )
    assert_invoke activity, dataset: ["one", "two", "three"], current_user: Object, expected_ctx_variables: {collected_from_each: ["one-0-Object", "two-1-Object", "three-2-Object"]}
  end

  it "allows taskWrap in Each" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item, In() => {:current_user => :user}, In() => [:item, :index]
      }

      def compute_item(ctx, item:, index:, user:, **)
        ctx[:value] = "#{item}-#{index.inspect}-#{user}"
      end
    end

    assert_invoke activity, dataset: ["one", "two", "three"], current_user: "Yogi", expected_ctx_variables: {collected_from_each: ["one-0-Yogi", "two-1-Yogi", "three-2-Yogi"]}
  end

  it "accepts operation" do
    nested_activity = Class.new(Trailblazer::Activity::Railway) do
      step :compute_item

      def compute_item(ctx, item:, index:, **)
        ctx[:value] = "#{item}-#{index.inspect}"
      end
    end

    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each(nested_activity)  # expects {:dataset}
    end
    # Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "doesn't override an existing ctx[:index]" do
   activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a, :b)
      include ComputeItem

      step Each(&DocsEachUnitTest.block), id: "Each/1"
      step :b
      def b(ctx, seq:, index:, **)
        ctx[:seq] = seq + [index]
      end

    end

    assert_invoke activity, dataset: [1,2,3], index: 9,
      expected_ctx_variables: {collected_from_each: ["1-0", "2-1", "3-2"]},
      seq: "[9]"
  end

  it "stops iterating when failure" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() {
        step :check
      }
      step :a

      include T.def_steps(:a)
      def check(ctx, item:, **)
        ctx[:value] = item.to_s #@ always collect the value, even in failure case.

        return false if item >= 3
        true
      end
    end

    #@ all works
    assert_invoke activity, dataset: [1,2],
      expected_ctx_variables: {collected_from_each: ["1", "2"]},
      seq: "[:a]"

    #@ fail at 3 but still collect 3rd iteration!
    Trailblazer::Developer.wtf?(activity, [{dataset: [1,2,3]}, {}])
    assert_invoke activity, dataset: [1,2,3],
      expected_ctx_variables: {collected_from_each: ["1", "2", "3"]},
      seq: "[]",
      terminus: :failure

    #@ fail at 3, skip 4
    assert_invoke activity, dataset: [1,2,3,4],
      expected_ctx_variables: {collected_from_each: ["1", "2", "3"]},
      seq: "[]",
      terminus: :failure
  end
end
