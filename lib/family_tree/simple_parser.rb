# frozen_string_literal: true

require "shellwords"

module FamilyTree
  class SimpleParser
    SUPPORTED_PERSON_KEYS = %w[name sex birth born death died].freeze
    SUPPORTED_FAMILY_KEYS = %w[husband wife children kids spouses].freeze

    def initialize(strict: false)
      @strict = strict
    end

    def parse_text(text)
      persons_by_id = {}
      families_by_id = {}
      warnings = []

      text.each_line.with_index(1) do |raw_line, line_no|
        line = strip_comment(raw_line).strip
        next if line.empty?

        tokens = parse_tokens(line, line_no)
        keyword = tokens.shift&.downcase
        case keyword
        when "person"
          parse_person_line(tokens, line_no, persons_by_id, warnings)
        when "family"
          parse_family_line(tokens, line_no, families_by_id, warnings)
        else
          warnings << "Line #{line_no}: unsupported statement '#{keyword}'."
        end
      end

      result = ParseResult.new(
        persons: persons_by_id.values.sort_by(&:id),
        families: families_by_id.values.sort_by(&:id),
        warnings: warnings
      )

      if @strict && result.warnings.any?
        raise ParseError, "Unsupported statements in strict mode:\n#{result.warnings.join("\n")}"
      end

      result
    end

    private

    def strip_comment(raw_line)
      raw_line.sub(/#.*/, "")
    end

    def parse_tokens(line, line_no)
      Shellwords.split(line)
    rescue ArgumentError => e
      raise ParseError, "Line #{line_no}: #{e.message}"
    end

    def parse_person_line(tokens, line_no, persons_by_id, warnings)
      id = tokens.shift
      if blank?(id)
        raise ParseError, "Line #{line_no}: person id is required."
      end
      if persons_by_id.key?(id)
        warnings << "Line #{line_no}: duplicate person id '#{id}', keeping first record."
        return
      end

      attrs = parse_attributes(tokens, line_no)
      unknown_keys = attrs.keys - SUPPORTED_PERSON_KEYS
      unknown_keys.each do |key|
        warnings << "Line #{line_no}: unsupported person attribute '#{key}'."
      end

      name = attrs["name"] || id
      birth = extract_year(attrs["birth"] || attrs["born"])
      death = extract_year(attrs["death"] || attrs["died"])
      sex = attrs["sex"]

      persons_by_id[id] = Person.new(
        id: id,
        name: name,
        sex: blank?(sex) ? nil : sex,
        birth_year: birth,
        death_year: death
      )
    end

    def parse_family_line(tokens, line_no, families_by_id, warnings)
      id = tokens.shift
      if blank?(id)
        raise ParseError, "Line #{line_no}: family id is required."
      end
      if families_by_id.key?(id)
        warnings << "Line #{line_no}: duplicate family id '#{id}', keeping first record."
        return
      end

      attrs = parse_attributes(tokens, line_no)
      unknown_keys = attrs.keys - SUPPORTED_FAMILY_KEYS
      unknown_keys.each do |key|
        warnings << "Line #{line_no}: unsupported family attribute '#{key}'."
      end

      husband_id = attrs["husband"]
      wife_id = attrs["wife"]
      spouse_ids = list_value(attrs["spouses"])
      husband_id ||= spouse_ids[0]
      wife_id ||= spouse_ids[1]

      child_ids = list_value(attrs["children"] || attrs["kids"])
      families_by_id[id] = Family.new(
        id: id,
        husband_id: blank?(husband_id) ? nil : husband_id,
        wife_id: blank?(wife_id) ? nil : wife_id,
        child_ids: child_ids
      )
    end

    def parse_attributes(tokens, line_no)
      attrs = {}
      tokens.each do |token|
        key, value = token.split("=", 2)
        if value.nil?
          raise ParseError, "Line #{line_no}: expected key=value token, got '#{token}'."
        end
        attrs[key.downcase] = value
      end
      attrs
    end

    def list_value(value)
      return [] if blank?(value)

      value.split(",").map(&:strip).reject(&:empty?).uniq
    end

    def blank?(value)
      value.nil? || value.strip.empty?
    end

    def extract_year(value)
      return nil if blank?(value)

      match = value.match(/(\d{4})/)
      match && match[1]
    end
  end
end
