# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentSymbolExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentSymbol, "document_symbol"

  def test_document_symbol_addons
    source = <<~RUBY
      class Foo
        test "foo" do
        end
      end
    RUBY

    test_addon(:create_document_symbol_addon, source: source) do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      })

      assert_nil(response.error, response.error&.full_message)

      response = response.response

      assert_equal(1, response.count)
      assert_equal("Foo", response.first.name)

      test_symbol = response.first.children.first
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::METHOD, test_symbol.kind)
    end
  end

  def test_rake_document_symbol_addon
    source = <<~RUBY
      namespace :foo do
        namespace :bar do
          task :one
          task two: []
          task "three"
          task "four" => []
          file :five
          directory :six
          multitask :seven
        end
      end
    RUBY

    test_addon(:create_document_symbol_addon, source: source, path: "/fake.rake") do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rake" } },
      })

      assert_nil(response.error, response.error&.full_message)

      response = response.response

      assert_equal(1, response.count)
      assert_equal("foo", response.first.name)
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::MODULE, response.first.kind)

      bar = response.first.children.first
      assert_equal("bar", bar.name)
      assert_equal(LanguageServer::Protocol::Constant::SymbolKind::MODULE, bar.kind)

      tasks = bar.children
      assert_equal(7, tasks.count)
      assert_equal("one", tasks[0].name)
      assert_equal("two", tasks[1].name)
      assert_equal("three", tasks[2].name)
      assert_equal("four", tasks[3].name)
      assert_equal("five", tasks[4].name)
      assert_equal("six", tasks[5].name)
      assert_equal("seven", tasks[6].name)
      assert(tasks.all? { |task| task.kind == LanguageServer::Protocol::Constant::SymbolKind::METHOD })
    end

    test_addon(:create_document_symbol_addon, source: source, path: "/fake.rb") do |executor|
      response = executor.execute({
        method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///fake.rb" } },
      })

      assert_nil(response.error, response.error&.full_message)

      response = response.response

      assert_empty(response)
    end
  end

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri)

    dispatcher = Prism::Dispatcher.new
    listener = RubyLsp::Requests::DocumentSymbol.new(uri, dispatcher)
    dispatcher.dispatch(document.tree)
    listener.perform
  end

  private

  def create_document_symbol_addon
    Class.new(RubyLsp::Addon) do
      def activate(message_queue); end

      def name
        "Document SymbolsAddon"
      end

      def deactivate; end

      def create_document_symbol_listener(response_builder, uri, dispatcher)
        klass = Class.new do
          include RubyLsp::Requests::Support::Common

          def initialize(response_builder, dispatcher)
            @response_builder = response_builder
            dispatcher.register(self, :on_call_node_enter)
          end

          def on_call_node_enter(node)
            parent = @response_builder.last
            T.bind(self, RubyLsp::Requests::Support::Common)
            message_value = node.message
            arguments = node.arguments&.arguments
            return unless message_value == "test" && arguments&.any?

            parent.children << RubyLsp::Interface::DocumentSymbol.new(
              name: arguments.first.content,
              kind: LanguageServer::Protocol::Constant::SymbolKind::METHOD,
              selection_range: range_from_node(node),
              range: range_from_node(node),
            )
          end
        end

        T.unsafe(klass).new(response_builder, dispatcher)
      end
    end
  end

  def rake_document_symbol_addon
    RubyLsp::Addons::Rake
  end
end
