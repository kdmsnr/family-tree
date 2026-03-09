# frozen_string_literal: true

require_relative "test_helper"

class ParserTest < Minitest::Test
  def test_parses_supported_tags_and_relationships
    text = File.read(fixture_path("basic.ged"))
    result = FamilyTree::Parser.new.parse_text(text)

    assert_equal 3, result.persons.size
    assert_equal 1, result.families.size
    assert_empty result.warnings

    john = result.persons.find { |person| person.id == "I1" }
    assert_equal "John Doe", john.name
    assert_equal "M", john.sex
    assert_equal "1900", john.birth_year
    assert_equal "1979", john.death_year

    family = result.families.first
    assert_equal "I1", family.husband_id
    assert_equal "I2", family.wife_id
    assert_equal ["I3"], family.child_ids
  end

  def test_warns_for_unsupported_tags
    text = File.read(fixture_path("unknown_tag.ged"))
    result = FamilyTree::Parser.new.parse_text(text)

    refute_empty result.warnings
    assert_includes result.warnings.join("\n"), "OCCU"
  end

  def test_strict_mode_fails_when_warnings_exist
    text = File.read(fixture_path("unknown_tag.ged"))

    error = assert_raises(FamilyTree::ParseError) do
      FamilyTree::Parser.new(strict: true).parse_text(text)
    end

    assert_includes error.message, "strict mode"
  end

  def test_falls_back_to_id_when_name_missing
    text = <<~GEDCOM
      0 @I1@ INDI
      1 SEX M
      0 TRLR
    GEDCOM
    result = FamilyTree::Parser.new.parse_text(text)
    assert_equal "I1", result.persons.first.name
  end

  def test_parses_indi_object_file_as_image_path
    text = <<~GEDCOM
      0 @I1@ INDI
      1 NAME Jon /Snow/
      1 OBJE
      2 FILE images/jon-snow.jpg
      0 TRLR
    GEDCOM

    result = FamilyTree::Parser.new.parse_text(text)
    assert_equal "images/jon-snow.jpg", result.persons.first.image_path
  end
end
