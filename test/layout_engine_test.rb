# frozen_string_literal: true

require_relative "test_helper"

class LayoutEngineTest < Minitest::Test
  def test_places_spouses_in_same_generation
    text = File.read(fixture_path("basic.ged"))
    parse_result = FamilyTree::Parser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    assert_in_delta node_by_id["I1"].y, node_by_id["I2"].y, 0.01
  end

  def test_places_children_below_parents
    text = File.read(fixture_path("basic.ged"))
    parse_result = FamilyTree::Parser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    assert_operator node_by_id["I3"].y, :>, node_by_id["I1"].y
    assert_operator node_by_id["I3"].y, :>, node_by_id["I2"].y
  end

  def test_keeps_siblings_on_same_generation_and_nearby
    text = File.read(fixture_path("siblings.ged"))
    parse_result = FamilyTree::Parser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    assert_in_delta node_by_id["I3"].y, node_by_id["I4"].y, 0.01
    distance = (node_by_id["I4"].x - node_by_id["I3"].x).abs
    assert_operator distance, :<, 260.0
  end

  def test_adds_missing_person_nodes
    text = File.read(fixture_path("simple_unknown.ftree"))
    parse_result = FamilyTree::SimpleParser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    assert node_by_id["p2"].missing
    assert node_by_id["p3"].missing
  end

  def test_preserves_declared_sibling_order_in_showcase_sample
    text = File.read(File.expand_path("../samples/family-showcase.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "family-showcase.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    assert_operator node_by_id["g1b"].x, :<, node_by_id["g1m"].x
    assert_operator node_by_id["g1m"].x, :<, node_by_id["g1s"].x

    assert_operator node_by_id["g2f1"].x, :<, node_by_id["g2m2"].x
    assert_operator node_by_id["g2m2"].x, :<, node_by_id["g2f2"].x
  end

  def test_single_child_is_centered_under_spouses_in_showcase
    text = File.read(File.expand_path("../samples/family-showcase.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "family-showcase.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    taro_center = node_center_x(node_by_id["g3m1"])
    masuo_sazae_center = (node_center_x(node_by_id["g2m1"]) + node_center_x(node_by_id["g2f1"])) / 2.0
    assert_in_delta masuo_sazae_center, taro_center, 0.5

    ikura_center = node_center_x(node_by_id["g3m2"])
    norisuke_taiko_center = (node_center_x(node_by_id["g2m3"]) + node_center_x(node_by_id["g2f3"])) / 2.0
    assert_in_delta norisuke_taiko_center, ikura_center, 0.5
  end

  def test_does_not_overlap_nodes_in_jojo_showcase
    text = File.read(File.expand_path("../samples/jojo-showcase.ftree", __dir__))
    parse_result = FamilyTree::InputParser.new.parse_text(
      text,
      format: "simple",
      input_path: "jojo-showcase.ftree"
    )
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node_by_id = layout.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

    holy = node_by_id.fetch("g4j1f")
    josuke = node_by_id.fetch("g4j2m")
    holy_right = holy.x + holy.width
    josuke_right = josuke.x + josuke.width

    overlaps = holy_right > josuke.x && josuke_right > holy.x
    refute overlaps
  end

  def test_carries_image_path_from_person_to_layout_node
    text = <<~TREE
      person p1 name="Taro" image=images/taro.png
    TREE
    parse_result = FamilyTree::SimpleParser.new.parse_text(text)
    layout = FamilyTree::LayoutEngine.new.layout(parse_result)
    node = layout.nodes.find { |item| item.id == "p1" }

    assert_equal "images/taro.png", node.image_path
  end

  private

  def node_center_x(node)
    node.x + (node.width / 2.0)
  end
end
