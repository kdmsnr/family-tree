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

  def test_connects_branch_to_sibling_bus_when_branch_is_outside_child_range
    layout = FamilyTree::LayoutResult.new(
      nodes: [
        FamilyTree::LayoutNode.new(
          id: "p1",
          label: "Parent",
          x: 0.0,
          y: 0.0,
          width: 100.0,
          height: 50.0,
          missing: false
        ),
        FamilyTree::LayoutNode.new(
          id: "c1",
          label: "Child 1",
          x: 300.0,
          y: 200.0,
          width: 100.0,
          height: 50.0,
          missing: false
        ),
        FamilyTree::LayoutNode.new(
          id: "c2",
          label: "Child 2",
          x: 500.0,
          y: 200.0,
          width: 100.0,
          height: 50.0,
          missing: false
        )
      ],
      families: [
        FamilyTree::LayoutFamily.new(
          id: "f1",
          spouse_ids: ["p1"],
          child_ids: %w[c1 c2]
        )
      ],
      canvas_width: 800,
      canvas_height: 320
    )

    svg = FamilyTree::Renderer.new.render(layout)
    assert_includes svg, "<line x1=\"50.00\" y1=\"94.00\" x2=\"550.00\" y2=\"94.00\"/>"
  end

  def test_renders_node_image_when_person_has_image_path
    text = <<~TREE
      person p1 name="Taro" image=images/taro.png
    TREE
    parse_result = FamilyTree::SimpleParser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)

    svg = FamilyTree::Renderer.new.render(layout)
    assert_includes svg, "id=\"node-images\""
    assert_includes svg, "href=\"images/taro.png\""
    assert_includes svg, "text-anchor=\"start\""
  end

  def test_offsets_spouse_anchors_for_multiple_marriages_of_same_person
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    daemon = node_by_id.fetch("g1t5m")

    daemon_bottom = format("%.2f", daemon.y + daemon.height)
    leg_xs = svg
      .scan(/<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/)
      .select { |x1, y1, x2, _y2| y1 == daemon_bottom && x1 == x2 }
      .map(&:first)
      .uniq

    assert_operator leg_xs.length, :>=, 2
  end

  def test_separates_marriage_rows_for_multiple_marriages
    text = <<~TREE
      person h name="Daemon"
      person w1 name="Wife1"
      person w2 name="Wife2"
      person c1 name="Child1"
      person c2 name="Child2"
      family f1 husband=h wife=w1 children=c1
      family f2 husband=h wife=w2 children=c2
    TREE
    parse_result = FamilyTree::InputParser.new.parse_text(text, format: "simple", input_path: "multi.ftree")
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    horizontal_y_values = spouse_group
      .scan(/<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/)
      .select { |_x1, y1, _x2, y2| y1 == y2 }
      .map { |_x1, y1, _x2, _y2| y1.to_f }
      .uniq
      .sort

    assert_operator horizontal_y_values.length, :>=, 2
    assert_operator (horizontal_y_values.last - horizontal_y_values.first), :>=, 16.0
  end

  def test_renders_bridge_paths_for_crossing_lines
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    assert_includes svg, "id=\"child-bridge-cutouts\""
    assert_includes svg, "id=\"spouse-bridges\""
    assert_includes svg, "id=\"child-bridges\""
    assert_match(/<path d="M [0-9.]+ [0-9.]+ A [0-9.]+ [0-9.]+ 0 0 1 [0-9.]+ [0-9.]+ A [0-9.]+ [0-9.]+ 0 0 1 [0-9.]+ [0-9.]+"\/>/, svg)
  end

  def test_adds_bridge_for_all_cross_intersections
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    renderer = FamilyTree::Renderer.new
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    spouse_edges, child_edges = renderer.send(:edge_lines, layout.families, node_by_id)
    all_edges = spouse_edges + child_edges

    expected_points = renderer.send(:dedupe_bridge_points, (
      renderer.send(:bridge_points_for, horizontal_lines: spouse_edges, all_lines: all_edges) +
      renderer.send(:bridge_points_for, horizontal_lines: child_edges, all_lines: all_edges)
    ))

    svg = renderer.render(layout)
    bridge_points = svg.scan(
      /<path d="M ([0-9.]+) ([0-9.]+) A [0-9.]+ [0-9.]+ 0 0 1 ([0-9.]+) [0-9.]+ A [0-9.]+ [0-9.]+ 0 0 1 ([0-9.]+) [0-9.]+"\/>/
    ).map do |left_x, y, center_x, right_x|
      # The parsed path encodes one bridge whose center is center_x/y.
      [center_x.to_f, y.to_f, left_x.to_f, right_x.to_f]
    end

    missing = expected_points.reject do |point|
      bridge_points.any? do |center_x, y, _left_x, _right_x|
        (center_x - point[:x]).abs <= 0.01 && (y - point[:y]).abs <= 0.01
      end
    end

    assert_empty missing
  end

  def test_avoids_overlapping_vertical_child_segments_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    child_group = svg[/<g id="child-edges"[^>]*>(.*?)<\/g>/m, 1]
    segments = child_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
    vertical = segments
      .select { |segment| (segment[:x1] - segment[:x2]).abs <= 0.01 }
      .map do |segment|
        y1, y2 = [segment[:y1], segment[:y2]].minmax
        { x: segment[:x1], y1: y1, y2: y2 }
      end

    overlaps = []
    vertical.combination(2) do |left, right|
      next unless (left[:x] - right[:x]).abs <= 0.01

      overlap_top = [left[:y1], right[:y1]].max
      overlap_bottom = [left[:y2], right[:y2]].min
      overlaps << [left[:x], overlap_top, overlap_bottom] if (overlap_bottom - overlap_top) > 0.5
    end

    assert_empty overlaps
  end

  def test_keeps_overlapping_child_buses_apart_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    child_group = svg[/<g id="child-edges"[^>]*>(.*?)<\/g>/m, 1]
    segments = child_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
    horizontal = segments
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1] }
      end

    too_close = []
    horizontal.combination(2) do |left, right|
      next if left[:x2] < right[:x1] || right[:x2] < left[:x1]
      next unless (left[:y] - right[:y]).abs < 10.0

      too_close << [left, right]
    end

    assert_empty too_close
  end
end
