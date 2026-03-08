# frozen_string_literal: true

require_relative "test_helper"

class RendererTest < Minitest::Test
  def test_renders_svg_from_layout
    text = File.read(fixture_path("basic.ged"))
    parse_result = FamilyTree::Parser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)

    svg = FamilyTree::Renderer.new.render(layout)
    assert_includes svg, "<svg"
    assert_includes svg, "id=\"child-edge-halos\""
    assert_includes svg, "id=\"spouse-edges\""
    assert_includes svg, "id=\"child-edges\""
    assert_includes svg, "stroke-dasharray=\"5 3\""
    assert_includes svg, "<line"
    assert_includes svg, "John Doe"
  end

  def test_marks_missing_nodes_as_dashed
    text = File.read(fixture_path("simple_unknown.ftree"))
    parse_result = FamilyTree::SimpleParser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)

    svg = FamilyTree::Renderer.new.render(layout)
    assert_includes svg, "stroke-dasharray"
    assert_includes svg, ">p2<"
  end

  def test_offsets_spouse_legs_to_avoid_nagie_cross
    text = File.read(File.expand_path("../samples/family-showcase.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "family-showcase.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    refute_includes svg, "<line x1=\"656.00\" y1=\"288.00\" x2=\"656.00\" y2=\"316.00\"/>"
  end

  def test_avoids_overlapping_wakame_and_norisuke_vertical_child_lines
    text = File.read(File.expand_path("../samples/family-showcase.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "family-showcase.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    refute_includes svg, "<line x1=\"762.00\" y1=\"316.00\" x2=\"762.00\" y2=\"347.00\"/>"
  end
end
