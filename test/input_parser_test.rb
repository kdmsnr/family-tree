# frozen_string_literal: true

require_relative "test_helper"

class InputParserTest < Minitest::Test
  def test_auto_detects_gedcom_by_extension
    text = File.read(fixture_path("basic.ged"))
    result = FamilyTree::InputParser.new.parse_text(text, input_path: "basic.ged")
    assert_equal 3, result.persons.size
  end

  def test_auto_detects_simple_by_extension
    text = File.read(fixture_path("simple.ftree"))
    result = FamilyTree::InputParser.new.parse_text(text, input_path: "simple.ftree")
    assert_equal 3, result.persons.size
  end

  def test_explicit_format_overrides_extension
    text = File.read(fixture_path("simple.ftree"))
    result = FamilyTree::InputParser.new.parse_text(text, input_path: "any.txt", format: "simple")
    assert_equal 1, result.families.size
  end

  def test_unknown_format_errors
    text = File.read(fixture_path("simple.ftree"))
    error = assert_raises(FamilyTree::ParseError) do
      FamilyTree::InputParser.new.parse_text(text, format: "yaml")
    end

    assert_includes error.message, "Unknown input format"
  end
end
