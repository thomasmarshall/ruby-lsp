# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Addons
    class Rake < Addon
      class DocumentSymbolListener
        extend T::Sig
        include RubyLsp::Requests::Support::Common

        RAKE_TASKS = T.let([:task, :file, :directory, :multitask].freeze, T::Array[Symbol])

        sig do
          params(
            response_builder: ResponseBuilders::DocumentSymbol,
            dispatcher: Prism::Dispatcher,
          ).void
        end
        def initialize(response_builder, dispatcher)
          @response_builder = response_builder
          dispatcher.register(self, :on_call_node_enter, :on_call_node_leave)
        end

        sig { params(node: Prism::CallNode).void }
        def on_call_node_enter(node)
          if node.name == :namespace
            handle_namespace(node)
          elsif RAKE_TASKS.include?(node.name)
            handle_task(node)
          end
        end

        sig { params(node: Prism::CallNode).void }
        def on_call_node_leave(node)
          if node.name == :namespace
            @response_builder.pop
          end
        end

        private

        sig { params(node: Prism::CallNode).void }
        def handle_namespace(node)
          arguments = node.arguments
          return unless arguments

          name_argument = arguments.arguments.first
          return unless name_argument

          name = case name_argument
          when Prism::SymbolNode
            name_argument.value
          end

          return unless name

          symbol = Interface::DocumentSymbol.new(
            name: name,
            kind: Constant::SymbolKind::MODULE,
            range: range_from_node(name_argument),
            selection_range: range_from_node(name_argument),
            children: [],
          )
          @response_builder.last.children << symbol
          @response_builder << symbol
        end

        sig { params(node: Prism::CallNode).void }
        def handle_task(node)
          arguments = node.arguments
          return unless arguments

          name_argument = arguments.arguments.first
          return unless name_argument

          name = case name_argument
          when Prism::SymbolNode then name_argument.value
          when Prism::StringNode then name_argument.content
          when Prism::KeywordHashNode
            first_element = name_argument.elements.first
            case first_element
            when Prism::AssocNode
              key = first_element.key
              case key
              when Prism::SymbolNode then key.value
              when Prism::StringNode then key.content
              end
            end
          end

          return unless name

          @response_builder.last.children << Interface::DocumentSymbol.new(
            name: name,
            kind: Constant::SymbolKind::METHOD,
            range: range_from_node(name_argument),
            selection_range: range_from_node(name_argument),
          )
        end
      end

      RAKE_FILENAME = T.let(/(Rakefile|\.rake)$/, Regexp)

      sig { override.params(message_queue: Thread::Queue).void }
      def activate(message_queue)
      end

      sig { override.void }
      def deactivate
      end

      sig { override.returns(String) }
      def name
        "Rake"
      end

      sig do
        override.params(
          response_builder: ResponseBuilders::DocumentSymbol,
          uri: URI::Generic,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def create_document_symbol_listener(response_builder, uri, dispatcher)
        return unless uri.to_standardized_path&.match?(RAKE_FILENAME)

        DocumentSymbolListener.new(response_builder, dispatcher)
      end
    end
  end
end
