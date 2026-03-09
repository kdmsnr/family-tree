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

  def test_assigns_lane_offsets_by_overlap_and_prefers_short_spans
    renderer = FamilyTree::Renderer.new
    entries = [
      {
        family: FamilyTree::LayoutFamily.new(id: "long", spouse_ids: %w[l1 l2], child_ids: []),
        spouse_nodes: [
          FamilyTree::LayoutNode.new(id: "l1", label: "L1", x: 80.0, y: 0.0, width: 100.0, height: 60.0, missing: false),
          FamilyTree::LayoutNode.new(id: "l2", label: "L2", x: 300.0, y: 0.0, width: 100.0, height: 60.0, missing: false)
        ],
        child_nodes: []
      },
      {
        family: FamilyTree::LayoutFamily.new(id: "short", spouse_ids: %w[s1 s2], child_ids: []),
        spouse_nodes: [
          FamilyTree::LayoutNode.new(id: "s1", label: "S1", x: 120.0, y: 0.0, width: 100.0, height: 60.0, missing: false),
          FamilyTree::LayoutNode.new(id: "s2", label: "S2", x: 180.0, y: 0.0, width: 100.0, height: 60.0, missing: false)
        ],
        child_nodes: []
      },
      {
        family: FamilyTree::LayoutFamily.new(id: "far", spouse_ids: %w[f1 f2], child_ids: []),
        spouse_nodes: [
          FamilyTree::LayoutNode.new(id: "f1", label: "F1", x: 520.0, y: 0.0, width: 100.0, height: 60.0, missing: false),
          FamilyTree::LayoutNode.new(id: "f2", label: "F2", x: 700.0, y: 0.0, width: 100.0, height: 60.0, missing: false)
        ],
        child_nodes: []
      }
    ]

    offsets = renderer.send(:assign_lane_offsets, entries)

    assert_in_delta 0.0, offsets.fetch("short"), 0.01
    assert_in_delta FamilyTree::Renderer::EDGE_LANE_GAP, offsets.fetch("long"), 0.01
    assert_in_delta 0.0, offsets.fetch("far"), 0.01
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
      .select { |segment| (segment[:x2] - segment[:x1]) >= 24.0 }

    too_close = []
    horizontal.combination(2) do |left, right|
      next if left[:x2] < right[:x1] || right[:x2] < left[:x1]
      next unless (left[:y] - right[:y]).abs < 10.0

      too_close << [left, right]
    end

    assert_empty too_close
  end

  def test_avoids_child_verticals_running_through_corlys_node
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    corlys = node_by_id.fetch("g0v1m")

    child_group = svg[/<g id="child-edges"[^>]*>(.*?)<\/g>/m, 1]
    segments = child_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end

    corlys_left = corlys.x + 0.01
    corlys_right = corlys.x + corlys.width - 0.01
    corlys_top = corlys.y + 0.01
    corlys_bottom = corlys.y + corlys.height - 0.01
    offending = segments.select do |segment|
      next false unless (segment[:x1] - segment[:x2]).abs <= 0.01
      next false unless segment[:x1] > corlys_left && segment[:x1] < corlys_right

      y_top, y_bottom = [segment[:y1], segment[:y2]].minmax
      y_top < corlys_bottom && y_bottom > corlys_top
    end

    assert_empty offending
  end

  def test_keeps_child_buses_away_from_spouse_rows_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    child_group = svg[/<g id="child-edges"[^>]*>(.*?)<\/g>/m, 1]
    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    child_horizontals = child_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1] }
      end
      .select { |segment| (segment[:x2] - segment[:x1]) >= 24.0 }

    spouse_horizontals = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1] }
      end
      .select { |segment| (segment[:x2] - segment[:x1]) >= 24.0 }

    too_close = []
    child_horizontals.each do |child|
      spouse_horizontals.each do |spouse|
        next if child[:x2] < spouse[:x1] || spouse[:x2] < child[:x1]
        next unless (child[:y] - spouse[:y]).abs < 10.0

        too_close << [child, spouse]
      end
    end

    assert_empty too_close
  end

  def test_keeps_overlapping_spouse_rows_apart_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    spouse_horizontals = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1], width: x2 - x1 }
      end
      .select { |segment| segment[:width] >= 180.0 }

    too_close = []
    spouse_horizontals.combination(2) do |left, right|
      next if left[:x2] < right[:x1] || right[:x2] < left[:x1]
      next unless (left[:y] - right[:y]).abs < 20.0

      too_close << [left, right]
    end

    assert_empty too_close
  end

  def test_does_not_draw_any_edge_line_through_node_interior_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    lines = svg.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end.uniq

    epsilon = 0.01
    overlaps = []
    lines.each do |segment|
      vertical = (segment[:x1] - segment[:x2]).abs <= epsilon
      horizontal = (segment[:y1] - segment[:y2]).abs <= epsilon
      next unless vertical || horizontal

      layout.nodes.each do |node|
        node_left = node.x + epsilon
        node_right = node.x + node.width - epsilon
        node_top = node.y + epsilon
        node_bottom = node.y + node.height - epsilon

        if vertical
          x = segment[:x1]
          next unless x > node_left && x < node_right

          y1, y2 = [segment[:y1], segment[:y2]].minmax
          overlap = [y2, node_bottom].min - [y1, node_top].max
          overlaps << [segment, node.id] if overlap > 0.0
        else
          y = segment[:y1]
          next unless y > node_top && y < node_bottom

          x1, x2 = [segment[:x1], segment[:x2]].minmax
          overlap = [x2, node_right].min - [x1, node_left].max
          overlaps << [segment, node.id] if overlap > 0.0
        end
      end
    end

    assert_empty overlaps
  end

  def test_does_not_draw_spouse_horizontal_segments_on_node_bottom_edges
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    spouse_horizontals = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1] }
      end

    epsilon = 0.01
    offending = []
    layout.nodes.each do |node|
      node_bottom = node.y + node.height
      node_left = node.x + epsilon
      node_right = node.x + node.width - epsilon
      spouse_horizontals.each do |segment|
        next unless (segment[:y] - node_bottom).abs <= epsilon

        overlap = [segment[:x2], node_right].min - [segment[:x1], node_left].max
        offending << [segment, node.id] if overlap > 0.0
      end
    end

    assert_empty offending
  end

  def test_avoids_overlapping_spouse_bend_segments_in_targaryen_sample
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    svg = FamilyTree::Renderer.new.render(layout)

    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    spouse_horizontals = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end
      .select { |segment| (segment[:y1] - segment[:y2]).abs <= 0.01 }
      .map do |segment|
        x1, x2 = [segment[:x1], segment[:x2]].minmax
        { x1: x1, x2: x2, y: segment[:y1], width: (x2 - x1) }
      end
      .select { |segment| segment[:width] >= 20.0 && segment[:width] <= 90.0 }

    overlapping = []
    spouse_horizontals.combination(2) do |left, right|
      next unless (left[:y] - right[:y]).abs <= 0.01
      next if left[:x2] <= right[:x1] || right[:x2] <= left[:x1]

      overlapping << [left, right]
    end

    assert_empty overlapping
  end

  def test_distributes_daemon_spouse_legs_on_both_sides_when_spouses_are_same_side
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    daemon = node_by_id.fetch("g1t5m")
    daemon_center = daemon.x + (daemon.width / 2.0)
    daemon_bottom = daemon.y + daemon.height

    svg = FamilyTree::Renderer.new.render(layout)
    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    leg_xs = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).filter_map do |x1, y1, x2, y2|
      x1_f = x1.to_f
      y1_f = y1.to_f
      x2_f = x2.to_f
      y2_f = y2.to_f
      next unless (y1_f - daemon_bottom).abs <= 0.01
      next unless (x1_f - x2_f).abs <= 0.01
      next unless y2_f > y1_f + 0.01

      x1_f
    end.uniq

    assert leg_xs.any? { |x| x < daemon_center }
    assert leg_xs.any? { |x| x > daemon_center }
  end

  def test_keeps_laenor_spouse_connection_without_long_detour
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    laenor = node_by_id.fetch("g1v2m")
    laenor_center = laenor.x + (laenor.width / 2.0)
    laenor_bottom = laenor.y + laenor.height

    svg = FamilyTree::Renderer.new.render(layout)
    spouse_group = svg[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    segments = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end

    leg_xs = segments.filter_map do |segment|
      next unless (segment[:x1] - segment[:x2]).abs <= 0.01
      next unless (segment[:y1] - laenor_bottom).abs <= 0.01
      next unless segment[:y2] > segment[:y1] + 0.01

      segment[:x1]
    end

    refute_empty leg_xs
    nearest = leg_xs.map { |x| (x - laenor_center).abs }.min
    assert_operator nearest, :<=, 50.0

    vertical_segments = segments.filter_map do |segment|
      next unless (segment[:x1] - segment[:x2]).abs <= 0.01

      y1, y2 = [segment[:y1], segment[:y2]].minmax
      { x: segment[:x1], y1: y1, y2: y2 }
    end
    horizontal_segments = segments.filter_map do |segment|
      next unless (segment[:y1] - segment[:y2]).abs <= 0.01

      x1, x2 = [segment[:x1], segment[:x2]].minmax
      { x1: x1, x2: x2, y: segment[:y1] }
    end

    detours = []
    leg_xs.each do |leg_x|
      leg_verticals = vertical_segments.select do |segment|
        (segment[:x] - leg_x).abs <= 0.01 &&
          (segment[:y1] - laenor_bottom).abs <= 0.01 &&
          segment[:y2] > (laenor_bottom + 0.01)
      end
      leg_verticals.each do |leg_vertical|
        bend_y = leg_vertical[:y2]
        connected_horizontals = horizontal_segments.select do |segment|
          next false unless (segment[:y] - bend_y).abs <= 0.01

          (segment[:x1] - leg_x).abs <= 0.01 || (segment[:x2] - leg_x).abs <= 0.01
        end
        connected_horizontals.each do |segment|
          other_x = (segment[:x1] - leg_x).abs <= 0.01 ? segment[:x2] : segment[:x1]
          continues_down = vertical_segments.any? do |vertical|
            (vertical[:x] - other_x).abs <= 0.01 &&
              vertical[:y1] <= (bend_y + 0.01) &&
              vertical[:y2] > (bend_y + 0.01)
          end
          detours << [leg_x, bend_y, other_x] if continues_down
        end
      end
    end

    assert_empty detours
  end

  def test_spouse_leg_prefers_lower_crossing_candidate_when_detour_is_reasonable
    renderer = FamilyTree::Renderer.new
    candidate_x = renderer.send(
      :resolve_spouse_leg_x,
      100.0,
      0.0,
      100.0,
      50.0,
      [],
      [{ x1: 90.0, x2: 110.0, y: 50.0 }],
      []
    )

    refute_in_delta 100.0, candidate_x, 0.01
  end

  def test_spouse_leg_avoids_huge_detour_for_single_crossing_reduction
    renderer = FamilyTree::Renderer.new
    candidate_x = renderer.send(
      :resolve_spouse_leg_x,
      100.0,
      0.0,
      100.0,
      50.0,
      [],
      [{ x1: 0.0, x2: 200.0, y: 50.0 }],
      []
    )

    assert_in_delta 100.0, candidate_x, 0.01
  end

  def test_does_not_run_spouse_vertical_along_laenor_left_edge
    text = File.read(File.expand_path("../samples/targaryen-three-eras.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "targaryen-three-eras.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
    laenor = node_by_id.fetch("g1v2m")

    spouse_group = FamilyTree::Renderer.new.render(layout)[/<g id="spouse-edges"[^>]*>(.*?)<\/g>/m, 1]
    segments = spouse_group.scan(
      /<line x1="([0-9.]+)" y1="([0-9.]+)" x2="([0-9.]+)" y2="([0-9.]+)"\/>/
    ).map do |x1, y1, x2, y2|
      { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }
    end

    epsilon = 0.01
    laenor_left = laenor.x
    edge_guard_margin = 10.0
    laenor_top = laenor.y + epsilon
    laenor_bottom = laenor.y + laenor.height - epsilon
    offending = segments.select do |segment|
      next false unless (segment[:x1] - segment[:x2]).abs <= epsilon
      next false unless segment[:x1] >= (laenor_left - edge_guard_margin)
      next false unless segment[:x1] <= (laenor_left + edge_guard_margin)

      y1, y2 = [segment[:y1], segment[:y2]].minmax
      [y2, laenor_bottom].min - [y1, laenor_top].max > 0.0
    end

    assert_empty offending
  end
end
