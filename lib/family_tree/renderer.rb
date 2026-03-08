# frozen_string_literal: true

require "fileutils"

module FamilyTree
  class Renderer
    NODE_RADIUS = 10.0
    FONT_SIZE = 13.0
    LINE_HEIGHT = 16.0
    SPOUSE_GAP = 16.0
    SIBLING_GAP = 28.0
    EDGE_LANE_GAP = 12.0
    MIN_VERTICAL_GAP = 10.0
    SPOUSE_INNER_OFFSET_RATIO = 0.28
    NODE_INNER_MARGIN = 12.0
    VERTICAL_COLLISION_THRESHOLD = 6.0
    MAX_BRANCH_SHIFT_STEPS = 8
    CHILD_STROKE_WIDTH = 1.4
    SPOUSE_STROKE_WIDTH = 2.0
    CHILD_HALO_WIDTH = 4.2

    def render(layout_result)
      node_by_id = layout_result.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
      spouse_edges, child_edges = edge_lines(layout_result.families, node_by_id)

      svg_lines = []
      svg_lines << %(<?xml version="1.0" encoding="UTF-8" standalone="no"?>)
      svg_lines << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{layout_result.canvas_width}" height="#{layout_result.canvas_height}" viewBox="0 0 #{layout_result.canvas_width} #{layout_result.canvas_height}" shape-rendering="geometricPrecision">)
      svg_lines << %(<rect x="0" y="0" width="#{layout_result.canvas_width}" height="#{layout_result.canvas_height}" fill="#ffffff"/>)
      svg_lines << %(<g id="child-edge-halos" stroke="#ffffff" stroke-width="#{CHILD_HALO_WIDTH}" fill="none" stroke-linecap="round" stroke-linejoin="round">)
      child_edges.each { |line| svg_lines << line }
      svg_lines << %(</g>)
      svg_lines << %(<g id="child-edges" stroke="#5d5d5d" stroke-width="#{CHILD_STROKE_WIDTH}" stroke-dasharray="5 3" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.92">)
      child_edges.each { |line| svg_lines << line }
      svg_lines << %(</g>)
      svg_lines << %(<g id="spouse-edges" stroke="#1f4e79" stroke-width="#{SPOUSE_STROKE_WIDTH}" fill="none" stroke-linecap="round" stroke-linejoin="round">)
      spouse_edges.each { |line| svg_lines << line }
      svg_lines << %(</g>)
      svg_lines << %(<g id="nodes">)
      layout_result.nodes.each do |node|
        fill = node.missing ? "#ffffff" : "#f8f8f8"
        stroke = node.missing ? "#888888" : "#333333"
        dash = node.missing ? %( stroke-dasharray="6 4") : ""
        svg_lines << %(<rect x="#{format_num(node.x)}" y="#{format_num(node.y)}" width="#{format_num(node.width)}" height="#{format_num(node.height)}" rx="#{NODE_RADIUS}" ry="#{NODE_RADIUS}" fill="#{fill}" stroke="#{stroke}"#{dash}/>)
      end
      svg_lines << %(</g>)
      svg_lines << %(<g id="labels" fill="#1f1f1f" font-family="Helvetica, Arial, sans-serif" font-size="#{FONT_SIZE}" text-anchor="middle">)
      layout_result.nodes.each do |node|
        label_lines(node).each { |line| svg_lines << line }
      end
      svg_lines << %(</g>)
      svg_lines << %(</svg>)

      svg_lines.join("\n")
    rescue StandardError => e
      raise RenderError, "Failed to render SVG: #{e.message}"
    end

    def render_to_file(layout_result, output_path)
      output_dir = File.dirname(output_path)
      FileUtils.mkdir_p(output_dir) unless output_dir == "."

      svg = render(layout_result)
      File.write(output_path, svg, mode: "wb")
      output_path
    end

    private

    def edge_lines(families, node_by_id)
      spouse_lines = []
      child_lines = []
      occupied_child_verticals = []
      entries = families.filter_map do |family|
        spouse_nodes = family.spouse_ids.filter_map { |person_id| node_by_id[person_id] }
        child_nodes = family.child_ids.filter_map { |person_id| node_by_id[person_id] }
        next if spouse_nodes.empty? && child_nodes.empty?

        {
          family: family,
          spouse_nodes: spouse_nodes,
          child_nodes: child_nodes
        }
      end

      lane_offsets = assign_lane_offsets(entries)
      entries.each do |entry|
        lane_offset = lane_offsets.fetch(entry[:family].id, 0.0)
        trunk_x, marriage_y = draw_spouse_section(
          spouse_lines,
          entry[:spouse_nodes],
          entry[:child_nodes],
          lane_offset
        )
        draw_children_section(
          child_lines,
          trunk_x,
          marriage_y,
          entry[:child_nodes],
          lane_offset,
          occupied_child_verticals
        )
      end

      [spouse_lines, child_lines]
    end

    def assign_lane_offsets(entries)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      entries.each do |entry|
        key = family_level_key(entry[:spouse_nodes], entry[:child_nodes])
        grouped[key] << entry
      end

      offsets = {}
      grouped.each_value do |group|
        sorted = group.sort_by { |entry| family_center_x(entry[:spouse_nodes], entry[:child_nodes]) }
        sorted.each_with_index do |entry, index|
          offsets[entry[:family].id] = index * EDGE_LANE_GAP
        end
      end
      offsets
    end

    def family_level_key(spouse_nodes, child_nodes)
      if spouse_nodes.any?
        spouse_nodes.map(&:y).max.round
      elsif child_nodes.any?
        child_nodes.map(&:y).min.round - 1_000
      else
        0
      end
    end

    def family_center_x(spouse_nodes, child_nodes)
      anchors = if spouse_nodes.any?
                  spouse_nodes.map { |node| node_center_x(node) }
                else
                  child_nodes.map { |node| node_center_x(node) }
                end

      return 0.0 if anchors.empty?

      anchors.sum / anchors.length.to_f
    end

    def draw_spouse_section(lines, spouse_nodes, child_nodes, lane_offset)
      if spouse_nodes.empty?
        child_anchors = child_nodes.map { |node| [node_center_x(node), node.y] }.sort_by(&:first)
        return [0.0, 0.0] if child_anchors.empty?

        trunk_x = child_anchors.sum(&:first) / child_anchors.length
        highest_child_y = child_anchors.map(&:last).min
        marriage_y = [highest_child_y - (SIBLING_GAP + SPOUSE_GAP + lane_offset), MIN_VERTICAL_GAP].max
        return [trunk_x, marriage_y]
      end

      anchors = spouse_anchors(spouse_nodes)
      baseline_marriage_y = anchors.map(&:last).max + SPOUSE_GAP
      marriage_y = baseline_marriage_y + lane_offset

      if anchors.length > 1
        anchors.each do |anchor_x, anchor_y|
          lines << svg_line(anchor_x, anchor_y, anchor_x, marriage_y)
        end
        lines << svg_line(anchors.first[0], marriage_y, anchors.last[0], marriage_y)
      else
        lines << svg_line(anchors.first[0], anchors.first[1], anchors.first[0], marriage_y)
      end

      trunk_x = anchors.sum(&:first) / anchors.length
      [trunk_x, marriage_y]
    end

    def spouse_anchors(spouse_nodes)
      sorted_nodes = spouse_nodes.sort_by { |node| node_center_x(node) }
      return sorted_nodes.map { |node| [node_center_x(node), node.y + node.height] } if sorted_nodes.length <= 1

      leftmost = node_center_x(sorted_nodes.first)
      rightmost = node_center_x(sorted_nodes.last)
      midpoint = (leftmost + rightmost) / 2.0

      sorted_nodes.map do |node|
        center_x = node_center_x(node)
        direction = if center_x < midpoint
                      1.0
                    elsif center_x > midpoint
                      -1.0
                    else
                      0.0
                    end

        offset = node.width * SPOUSE_INNER_OFFSET_RATIO
        raw_anchor_x = center_x + (direction * offset)
        min_x = node.x + NODE_INNER_MARGIN
        max_x = node.x + node.width - NODE_INNER_MARGIN
        anchor_x = [[raw_anchor_x, min_x].max, max_x].min

        [anchor_x, node.y + node.height]
      end
    end

    def draw_children_section(lines, trunk_x, marriage_y, child_nodes, lane_offset, occupied_verticals)
      return if child_nodes.empty?

      child_anchors = child_nodes.map { |node| [node_center_x(node), node.y] }.sort_by(&:first)
      min_child_y = child_anchors.map(&:last).min
      desired_sibling_y = marriage_y + SIBLING_GAP + (lane_offset * 0.25)
      sibling_y = [desired_sibling_y, min_child_y - MIN_VERTICAL_GAP].min
      sibling_y = marriage_y + MIN_VERTICAL_GAP if sibling_y <= marriage_y + MIN_VERTICAL_GAP

      branch_x = resolve_branch_x(
        trunk_x,
        marriage_y,
        sibling_y,
        child_anchors,
        occupied_verticals
      )

      if (branch_x - trunk_x).abs > 0.5
        lines << svg_line(trunk_x, marriage_y, branch_x, marriage_y)
      end

      lines << svg_line(branch_x, marriage_y, branch_x, sibling_y)
      register_vertical_segment(occupied_verticals, branch_x, marriage_y, sibling_y)

      if child_anchors.length > 1
        lines << svg_line(child_anchors.first[0], sibling_y, child_anchors.last[0], sibling_y)
      elsif (branch_x - child_anchors.first[0]).abs > 0.5
        lines << svg_line(branch_x, sibling_y, child_anchors.first[0], sibling_y)
      end

      child_anchors.each do |child_x, child_y|
        lines << svg_line(child_x, sibling_y, child_x, child_y)
        register_vertical_segment(occupied_verticals, child_x, sibling_y, child_y)
      end
    end

    def resolve_branch_x(base_x, y1, y2, child_anchors, occupied_verticals)
      child_center_x = child_anchors.sum(&:first) / child_anchors.length
      preferred_direction = child_center_x >= base_x ? 1.0 : -1.0

      candidate_offsets = [0.0]
      1.upto(MAX_BRANCH_SHIFT_STEPS) do |step|
        candidate_offsets << (preferred_direction * EDGE_LANE_GAP * step)
        candidate_offsets << (-preferred_direction * EDGE_LANE_GAP * step)
      end

      candidate_offsets.each do |offset|
        candidate_x = base_x + offset
        next if vertical_collision?(candidate_x, y1, y2, occupied_verticals)

        return candidate_x
      end

      base_x
    end

    def vertical_collision?(x, y1, y2, occupied_verticals)
      occupied_verticals.any? do |segment|
        next false unless (segment[:x] - x).abs <= VERTICAL_COLLISION_THRESHOLD

        ranges_overlap?(y1, y2, segment[:y1], segment[:y2])
      end
    end

    def register_vertical_segment(occupied_verticals, x, y1, y2)
      occupied_verticals << {
        x: x,
        y1: [y1, y2].min,
        y2: [y1, y2].max
      }
    end

    def ranges_overlap?(a1, a2, b1, b2)
      left = [a1, a2].min
      right = [a1, a2].max
      other_left = [b1, b2].min
      other_right = [b1, b2].max
      left <= other_right && other_left <= right
    end

    def label_lines(node)
      lines = node.label.to_s.split("\n")
      return [] if lines.empty?

      block_height = (lines.length - 1) * LINE_HEIGHT
      start_y = node.y + (node.height / 2.0) - (block_height / 2.0) + 4.0
      center_x = node_center_x(node)

      lines.each_with_index.map do |text, index|
        y = start_y + (index * LINE_HEIGHT)
        %(<text x="#{format_num(center_x)}" y="#{format_num(y)}">#{escape_xml(text)}</text>)
      end
    end

    def node_center_x(node)
      node.x + (node.width / 2.0)
    end

    def svg_line(x1, y1, x2, y2)
      %(<line x1="#{format_num(x1)}" y1="#{format_num(y1)}" x2="#{format_num(x2)}" y2="#{format_num(y2)}"/>)
    end

    def format_num(value)
      format("%.2f", value.to_f)
    end

    def escape_xml(text)
      text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
    end
  end
end
