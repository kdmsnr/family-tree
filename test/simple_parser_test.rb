# frozen_string_literal: true

require_relative "test_helper"

class SimpleParserTest < Minitest::Test
  def test_parses_simple_format
    text = File.read(fixture_path("simple.ftree"))
    result = FamilyTree::SimpleParser.new.parse_text(text)

    assert_equal 3, result.persons.size
    assert_equal 1, result.families.size
    assert_empty result.warnings

    person = result.persons.find { |item| item.id == "p1" }
    assert_equal "Taro Yamada", person.name
    assert_equal "1970", person.birth_year

    family = result.families.first
    assert_equal "p1", family.husband_id
    assert_equal "p2", family.wife_id
    assert_equal ["p3"], family.child_ids
  end

  def test_warns_for_unsupported_simple_attributes
    text = File.read(fixture_path("simple_unknown.ftree"))
    result = FamilyTree::SimpleParser.new.parse_text(text)

    refute_empty result.warnings
    assert_includes result.warnings.join("\n"), "occupation"
  end

  def test_strict_mode_fails_for_simple_warnings
    text = File.read(fixture_path("simple_unknown.ftree"))

    error = assert_raises(FamilyTree::ParseError) do
      FamilyTree::SimpleParser.new(strict: true).parse_text(text)
    end

    assert_includes error.message, "strict mode"
  end

  def test_parses_person_image_attribute
    text = <<~TREE
      person p1 name="Taro Yamada" image=images/taro.png
      person p2 name="Hanako Yamada"
      family f1 spouses=p1,p2
    TREE

    result = FamilyTree::SimpleParser.new.parse_text(text)
    person = result.persons.find { |item| item.id == "p1" }
    assert_equal "images/taro.png", person.image_path
  end
end
