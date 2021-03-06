require 'cucumber/core_ext/string'
require 'cucumber/step_match'
require 'cucumber/ast/location'

module Cucumber
  module Ast
    class Step #:nodoc:
      include HasLocation

      attr_reader :keyword, :name, :language
      attr_writer :step_collection, :options
      attr_accessor :feature_element, :exception, :multiline_arg

      INDENT = 2

      def initialize(language, location, keyword, name, multiline_arg=nil)
        @language, @location, @keyword, @name, @multiline_arg = language, location, keyword, name, multiline_arg
        @language || raise("Language is required!")
      end

      attr_reader :gherkin_statement
      def gherkin_statement(statement=nil)
        @gherkin_statement ||= statement
      end

      def background?
        false
      end

      def status
        # Step always has status skipped, because Step is always in a ScenarioOutline
        :skipped
      end

      def step_invocation
        StepInvocation.new(self, name, @multiline_arg, [])
      end

      def step_invocation_from_cells(cells)
        matched_cells = matched_cells(cells)

        delimited_arguments = delimit_argument_names(cells.to_hash)
        name                = replace_name_arguments(delimited_arguments)
        multiline_arg       = @multiline_arg.nil? ? nil : @multiline_arg.arguments_replaced(delimited_arguments)

        StepInvocation.new(self, name, multiline_arg, matched_cells)
      end

      def accept(visitor)
        visitor.visit_step(self) do
          # The only time a Step is visited is when it is in a ScenarioOutline.
          # Otherwise it's always StepInvocation that gets visited instead.
          status = :skipped
          exception = nil
          background = nil
          step_result = StepResult.new(keyword, first_match(visitor), @multiline_arg, status, exception, source_indent, background, file_colon_line) 
          step_result.accept(visitor)
        end
      end

      def first_match(visitor)
        # feature_element is always a ScenarioOutline in this case
        feature_element.each_example_row do |cells|
          argument_hash       = cells.to_hash
          delimited_arguments = delimit_argument_names(argument_hash)
          name_to_match       = replace_name_arguments(delimited_arguments)
          step_match          = visitor.runtime.step_match(name_to_match, name) rescue nil
          return step_match if step_match
        end
        NoStepMatch.new(self, name)
      end

      def to_sexp
        [:step, line, keyword, name, (@multiline_arg.nil? ? nil : @multiline_arg.to_sexp)].compact
      end

      def source_indent
        feature_element.source_indent(text_length)
      end

      def text_length(name=name)
        INDENT + INDENT + keyword.unpack('U*').length + name.unpack('U*').length
      end

      def backtrace_line
        @backtrace_line ||= feature_element.backtrace_line("#{keyword}#{name}", line) unless feature_element.nil?
      end

      def dom_id
        @dom_id ||= file_colon_line.gsub(/\//, '_').gsub(/\./, '_').gsub(/:/, '_')
      end

      private

      def matched_cells(cells)
        col_index = 0
        cells.select do |cell|
          header_cell = cell.table.header_cell(col_index)
          col_index += 1
          delimited = delimited(header_cell.value)
          name.index(delimited) || (@multiline_arg && @multiline_arg.has_text?(delimited))
        end
      end

      def delimit_argument_names(argument_hash)
        argument_hash.inject({}) { |h,(name,value)| h[delimited(name)] = value; h }
      end

      def delimited(s)
        "<#{s}>"
      end

      def replace_name_arguments(argument_hash)
        name_with_arguments_replaced = name
        argument_hash.each do |key, value|
          value ||= ''
          name_with_arguments_replaced = name_with_arguments_replaced.gsub(key, value)
        end
        name_with_arguments_replaced
      end
    end
  end
end
