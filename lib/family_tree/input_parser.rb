# frozen_string_literal: true

module FamilyTree
  class InputParser
    FORMATS = %w[auto gedcom simple].freeze

    def initialize(strict: false)
      @strict = strict
    end

    def parse_text(text, format: "auto", input_path: nil)
      normalized_format = normalize_format(format)
      parser = case normalized_format
               when "gedcom"
                 Parser.new(strict: @strict)
               when "simple"
                 SimpleParser.new(strict: @strict)
               else
                 parser_for_auto(text, input_path)
               end
      parser.parse_text(text)
    end

    private

    def normalize_format(format)
      value = format.to_s.downcase
      return "auto" if value.empty?
      return value if FORMATS.include?(value)

      raise ParseError, "Unknown input format '#{format}'. Use one of: #{FORMATS.join(', ')}."
    end

    def parser_for_auto(text, input_path)
      case detect_format(text, input_path)
      when "gedcom"
        Parser.new(strict: @strict)
      when "simple"
        SimpleParser.new(strict: @strict)
      else
        raise ParseError, "Could not detect input format. Use --format gedcom or --format simple."
      end
    end

    def detect_format(text, input_path)
      extension = File.extname(input_path.to_s).downcase
      return "gedcom" if extension == ".ged"
      return "simple" if %w[.ftree .family .tree].include?(extension)

      first_content_line = text.each_line.find { |line| !line.strip.empty? && !line.strip.start_with?("#") }
      return "simple" if first_content_line.nil?

      return "gedcom" if first_content_line.match?(/\A\d+\s+/)
      return "simple" if first_content_line.match?(/\A(person|family)\b/i)

      nil
    end
  end
end
