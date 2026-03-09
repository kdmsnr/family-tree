# frozen_string_literal: true

require "fileutils"

module FamilyTree
  class Renderer
    NODE_RADIUS = 10.0
    FONT_SIZE = 13.0
    LINE_HEIGHT = 16.0
    SPOUSE_GAP = 16.0
    SIBLING_GAP = 28.0
    SIBLING_LANE_OFFSET_FACTOR = 0.75
    EDGE_LANE_GAP = 12.0
    MIN_VERTICAL_GAP = 10.0
    MIN_SIBLING_BUS_VERTICAL_GAP = 10.0
    SPOUSE_INNER_OFFSET_RATIO = 0.28
    NODE_INNER_MARGIN = 12.0
    VERTICAL_COLLISION_THRESHOLD = 6.0
    MAX_BRANCH_SHIFT_STEPS = 8
    CHILD_STROKE_WIDTH = 1.4
    SPOUSE_STROKE_WIDTH = 2.0
    CHILD_HALO_WIDTH = 4.2
    SPOUSE_MULTI_FAMILY_OFFSET_GAP = 10.0
    MULTI_MARRIAGE_FAMILY_VERTICAL_GAP = 16.0
    BRIDGE_RADIUS = 4.0
    BRIDGE_CUTOUT_RADIUS = 5.8
    LINE_EPSILON = 0.01
    NODE_IMAGE_SIZE = 36.0
    NODE_IMAGE_MARGIN_LEFT = 8.0
    NODE_TEXT_GAP = 8.0
    NODE_TEXT_RIGHT_MARGIN = 8.0

    def render(layout_result)
      node_by_id = layout_result.nodes.each_with_object({}) { |node, acc| acc[node.id] = node }
      spouse_edges, child_edges = edge_lines(layout_result.families, node_by_id)
      all_edges = spouse_edges + child_edges
      child_bridge_points = bridge_points_for(horizontal_lines: child_edges, all_lines: all_edges)
      spouse_bridge_points = bridge_points_for(horizontal_lines: spouse_edges, all_lines: all_edges)
      bridge_cutouts = bridge_cutout_shapes(
        dedupe_bridge_points(child_bridge_points + spouse_bridge_points)
      )
      child_bridge_paths = child_bridge_points.map { |point| bridge_path(point[:x], point[:y]) }
      spouse_bridge_paths = spouse_bridge_points.map { |point| bridge_path(point[:x], point[:y]) }

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
      unless bridge_cutouts.empty?
        svg_lines << %(<g id="child-bridge-cutouts" fill="#ffffff">)
        bridge_cutouts.each { |line| svg_lines << line }
        svg_lines << %(</g>)
      end
      unless spouse_bridge_paths.empty?
        svg_lines << %(<g id="spouse-bridges" stroke="#1f4e79" stroke-width="#{SPOUSE_STROKE_WIDTH}" fill="none" stroke-linecap="round" stroke-linejoin="round">)
        spouse_bridge_paths.each { |line| svg_lines << line }
        svg_lines << %(</g>)
      end
      unless child_bridge_paths.empty?
        svg_lines << %(<g id="child-bridges" stroke="#5d5d5d" stroke-width="#{CHILD_STROKE_WIDTH}" fill="none" stroke-linecap="round" stroke-linejoin="round">)
        child_bridge_paths.each { |line| svg_lines << line }
        svg_lines << %(</g>)
      end
      svg_lines << %(<g id="nodes">)
      layout_result.nodes.each do |node|
        fill = node.missing ? "#ffffff" : "#f8f8f8"
        stroke = node.missing ? "#888888" : "#333333"
        dash = node.missing ? %( stroke-dasharray="6 4") : ""
        svg_lines << %(<rect x="#{format_num(node.x)}" y="#{format_num(node.y)}" width="#{format_num(node.width)}" height="#{format_num(node.height)}" rx="#{NODE_RADIUS}" ry="#{NODE_RADIUS}" fill="#{fill}" stroke="#{stroke}"#{dash}/>)
      end
      svg_lines << %(</g>)
      svg_lines << %(<g id="node-images">)
      layout_result.nodes.each do |node|
        line = node_image_line(node)
        svg_lines << line unless line.nil?
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
      occupied_child_horizontals = []
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
      spouse_anchor_offsets = assign_spouse_anchor_offsets(entries)
      family_vertical_offsets = assign_family_vertical_offsets(entries)
      entries.each do |entry|
        lane_offset = lane_offsets.fetch(entry[:family].id, 0.0)
        family_vertical_offset = family_vertical_offsets.fetch(entry[:family].id, 0.0)
        trunk_x, marriage_y = draw_spouse_section(
          spouse_lines,
          entry[:family].id,
          entry[:spouse_nodes],
          entry[:child_nodes],
          lane_offset,
          spouse_anchor_offsets,
          family_vertical_offset
        )
        draw_children_section(
          child_lines,
          trunk_x,
          marriage_y,
          entry[:child_nodes],
          lane_offset,
          occupied_child_verticals,
          occupied_child_horizontals
        )
      end

      [spouse_lines, child_lines]
    end

    def bridge_points_for(horizontal_lines:, all_lines:)
      horizontal_segments = horizontal_lines.filter_map { |line| parse_svg_line_segment(line) }
                                        .select { |segment| horizontal_segment?(segment) }
      vertical_segments = all_lines.filter_map { |line| parse_svg_line_segment(line) }
                                   .select { |segment| vertical_segment?(segment) }

      intersections = []
      horizontal_segments.each do |horizontal|
        left_x, right_x = [horizontal[:x1], horizontal[:x2]].minmax
        crossing_y = horizontal[:y1]
        vertical_segments.each do |vertical|
          crossing_x = vertical[:x1]
          min_y, max_y = [vertical[:y1], vertical[:y2]].minmax
          next unless crossing_x > (left_x + LINE_EPSILON)
          next unless crossing_x < (right_x - LINE_EPSILON)
          next unless crossing_y > (min_y + LINE_EPSILON)
          next unless crossing_y < (max_y - LINE_EPSILON)

          intersections << { x: crossing_x, y: crossing_y }
        end
      end

      dedupe_bridge_points(intersections)
    end

    def bridge_cutout_shapes(points)
      points.map do |point|
        %(<circle cx="#{format_num(point[:x])}" cy="#{format_num(point[:y])}" r="#{format_num(BRIDGE_CUTOUT_RADIUS)}"/>)
      end
    end

    def dedupe_bridge_points(points)
      seen = {}
      points.each_with_object([]) do |point, acc|
        key = "#{format('%.3f', point[:x])}:#{format('%.3f', point[:y])}"
        next if seen[key]

        seen[key] = true
        acc << point
      end
    end

    def parse_svg_line_segment(svg_line_text)
      match = svg_line_text.match(/x1="([^"]+)" y1="([^"]+)" x2="([^"]+)" y2="([^"]+)"/)
      return nil if match.nil?

      {
        x1: match[1].to_f,
        y1: match[2].to_f,
        x2: match[3].to_f,
        y2: match[4].to_f
      }
    end

    def horizontal_segment?(segment)
      (segment[:y1] - segment[:y2]).abs <= LINE_EPSILON &&
        (segment[:x1] - segment[:x2]).abs > LINE_EPSILON
    end

    def vertical_segment?(segment)
      (segment[:x1] - segment[:x2]).abs <= LINE_EPSILON &&
        (segment[:y1] - segment[:y2]).abs > LINE_EPSILON
    end

    def bridge_path(crossing_x, crossing_y)
      left_x = crossing_x - BRIDGE_RADIUS
      right_x = crossing_x + BRIDGE_RADIUS
      top_y = crossing_y - BRIDGE_RADIUS
      radius = format_num(BRIDGE_RADIUS)

      %(<path d="M #{format_num(left_x)} #{format_num(crossing_y)} A #{radius} #{radius} 0 0 1 #{format_num(crossing_x)} #{format_num(top_y)} A #{radius} #{radius} 0 0 1 #{format_num(right_x)} #{format_num(crossing_y)}"/>)
    end

    def assign_family_vertical_offsets(entries)
      families_by_person = Hash.new { |hash, key| hash[key] = [] }
      entries.each do |entry|
        entry[:spouse_nodes].each do |node|
          families_by_person[node.id] << entry
        end
      end

      offset_sum = Hash.new(0.0)
      contribution_count = Hash.new(0)
      families_by_person.each_value do |person_entries|
        unique_entries = person_entries.uniq
        next if unique_entries.length <= 1

        sorted_entries = unique_entries.sort_by do |entry|
          family_center_x(entry[:spouse_nodes], entry[:child_nodes])
        end
        center = (sorted_entries.length - 1) / 2.0
        sorted_entries.each_with_index do |entry, index|
          offset = (index - center) * MULTI_MARRIAGE_FAMILY_VERTICAL_GAP
          family_id = entry[:family].id
          offset_sum[family_id] += offset
          contribution_count[family_id] += 1
        end
      end

      offsets = {}
      offset_sum.each do |family_id, sum|
        offsets[family_id] = sum / contribution_count[family_id]
      end
      offsets
    end

    def assign_spouse_anchor_offsets(entries)
      families_by_person = Hash.new { |hash, key| hash[key] = [] }
      entries.each do |entry|
        entry[:spouse_nodes].each do |node|
          families_by_person[node.id] << entry
        end
      end

      offsets = {}
      families_by_person.each do |person_id, person_entries|
        unique_entries = person_entries.uniq
        next if unique_entries.length <= 1

        sorted_entries = unique_entries.sort_by do |entry|
          family_center_x(entry[:spouse_nodes], entry[:child_nodes])
        end
        center = (sorted_entries.length - 1) / 2.0
        sorted_entries.each_with_index do |entry, index|
          offset = (index - center) * SPOUSE_MULTI_FAMILY_OFFSET_GAP
          offsets[[entry[:family].id, person_id]] = offset
        end
      end
      offsets
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

    def draw_spouse_section(lines, family_id, spouse_nodes, child_nodes, lane_offset, spouse_anchor_offsets, family_vertical_offset)
      if spouse_nodes.empty?
        child_anchors = child_nodes.map { |node| [node_center_x(node), node.y] }.sort_by(&:first)
        return [0.0, 0.0] if child_anchors.empty?

        trunk_x = child_anchors.sum(&:first) / child_anchors.length
        highest_child_y = child_anchors.map(&:last).min
        marriage_y = [highest_child_y - (SIBLING_GAP + SPOUSE_GAP + lane_offset), MIN_VERTICAL_GAP].max
        marriage_y += family_vertical_offset
        marriage_y = [marriage_y, MIN_VERTICAL_GAP].max
        return [trunk_x, marriage_y]
      end

      anchors = spouse_anchors(spouse_nodes, family_id, spouse_anchor_offsets)
      baseline_marriage_y = anchors.map(&:last).max + SPOUSE_GAP
      marriage_y = baseline_marriage_y + lane_offset + family_vertical_offset
      min_marriage_y = anchors.map(&:last).max + MIN_VERTICAL_GAP
      marriage_y = [marriage_y, min_marriage_y].max

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

    def spouse_anchors(spouse_nodes, family_id, spouse_anchor_offsets)
      sorted_nodes = spouse_nodes.sort_by { |node| node_center_x(node) }
      if sorted_nodes.length <= 1
        return sorted_nodes.map do |node|
          base_x = node_center_x(node)
          adjusted_x = base_x + spouse_anchor_offsets.fetch([family_id, node.id], 0.0)
          min_x = node.x + NODE_INNER_MARGIN
          max_x = node.x + node.width - NODE_INNER_MARGIN
          anchor_x = [[adjusted_x, min_x].max, max_x].min
          [anchor_x, node.y + node.height]
        end
      end

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
        raw_anchor_x += spouse_anchor_offsets.fetch([family_id, node.id], 0.0)
        min_x = node.x + NODE_INNER_MARGIN
        max_x = node.x + node.width - NODE_INNER_MARGIN
        anchor_x = [[raw_anchor_x, min_x].max, max_x].min

        [anchor_x, node.y + node.height]
      end
    end

    def draw_children_section(lines, trunk_x, marriage_y, child_nodes, lane_offset, occupied_verticals, occupied_horizontals)
      return if child_nodes.empty?

      child_anchors = child_nodes.map { |node| [node_center_x(node), node.y] }.sort_by(&:first)
      min_child_y = child_anchors.map(&:last).min
      desired_sibling_y = marriage_y + SIBLING_GAP + (lane_offset * SIBLING_LANE_OFFSET_FACTOR)
      sibling_y, branch_x = resolve_sibling_geometry(
        trunk_x,
        marriage_y,
        desired_sibling_y,
        min_child_y,
        child_anchors,
        occupied_verticals,
        occupied_horizontals
      )

      if (branch_x - trunk_x).abs > 0.5
        lines << svg_line(trunk_x, marriage_y, branch_x, marriage_y)
      end

      lines << svg_line(branch_x, marriage_y, branch_x, sibling_y)
      register_vertical_segment(occupied_verticals, branch_x, marriage_y, sibling_y)

      if child_anchors.length > 1
        sibling_left_x = [child_anchors.first[0], branch_x].min
        sibling_right_x = [child_anchors.last[0], branch_x].max
        lines << svg_line(sibling_left_x, sibling_y, sibling_right_x, sibling_y)
        register_horizontal_segment(occupied_horizontals, sibling_left_x, sibling_right_x, sibling_y)
      elsif (branch_x - child_anchors.first[0]).abs > 0.5
        lines << svg_line(branch_x, sibling_y, child_anchors.first[0], sibling_y)
        register_horizontal_segment(
          occupied_horizontals,
          [branch_x, child_anchors.first[0]].min,
          [branch_x, child_anchors.first[0]].max,
          sibling_y
        )
      end

      child_anchors.each do |child_x, child_y|
        lines << svg_line(child_x, sibling_y, child_x, child_y)
        register_vertical_segment(occupied_verticals, child_x, sibling_y, child_y)
      end
    end

    def resolve_sibling_geometry(
      trunk_x,
      marriage_y,
      desired_sibling_y,
      min_child_y,
      child_anchors,
      occupied_verticals,
      occupied_horizontals
    )
      max_sibling_y = min_child_y - MIN_VERTICAL_GAP
      min_sibling_y = marriage_y + MIN_VERTICAL_GAP
      if max_sibling_y <= min_sibling_y
        sibling_y = [[desired_sibling_y, min_sibling_y].max, max_sibling_y].min
        branch_x = resolve_branch_x(
          trunk_x,
          marriage_y,
          sibling_y,
          child_anchors,
          occupied_verticals
        )
        return [sibling_y, branch_x]
      end

      step = [EDGE_LANE_GAP * 0.5, 4.0].max
      candidate_y = [[desired_sibling_y, min_sibling_y].max, max_sibling_y].min
      while candidate_y <= max_sibling_y + LINE_EPSILON
        candidate_branch_x = resolve_branch_x(
          trunk_x,
          marriage_y,
          candidate_y,
          child_anchors,
          occupied_verticals
        )
        sibling_left_x = [child_anchors.first[0], candidate_branch_x].min
        sibling_right_x = [child_anchors.last[0], candidate_branch_x].max

        collision = child_anchors.any? do |child_x, child_y|
          vertical_collision?(child_x, candidate_y, child_y, occupied_verticals)
        end
        bus_collision = horizontal_bus_collision?(
          sibling_left_x,
          sibling_right_x,
          candidate_y,
          occupied_horizontals
        )
        return [candidate_y, candidate_branch_x] unless collision || bus_collision

        candidate_y += step
      end

      final_branch_x = resolve_branch_x(
        trunk_x,
        marriage_y,
        max_sibling_y,
        child_anchors,
        occupied_verticals
      )
      [max_sibling_y, final_branch_x]
    end

    def horizontal_bus_collision?(x1, x2, y, occupied_horizontals)
      occupied_horizontals.any? do |segment|
        next false unless ranges_overlap?(x1, x2, segment[:x1], segment[:x2])

        (segment[:y] - y).abs < MIN_SIBLING_BUS_VERTICAL_GAP
      end
    end

    def register_horizontal_segment(occupied_horizontals, x1, x2, y)
      occupied_horizontals << {
        x1: [x1, x2].min,
        x2: [x1, x2].max,
        y: y
      }
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
      text_start_y = node.y + (node.height / 2.0) - (block_height / 2.0) + 4.0

      if node_has_image?(node)
        text_start_x = node_image_x(node) + NODE_IMAGE_SIZE + NODE_TEXT_GAP
        text_end_x = node.x + node.width - NODE_TEXT_RIGHT_MARGIN
        text_x = [text_start_x, text_end_x].min
        return lines.each_with_index.map do |text, index|
          y = text_start_y + (index * LINE_HEIGHT)
          %(<text x="#{format_num(text_x)}" y="#{format_num(y)}" text-anchor="start">#{escape_xml(text)}</text>)
        end
      end

      center_x = node_center_x(node)
      lines.each_with_index.map do |text, index|
        y = text_start_y + (index * LINE_HEIGHT)
        %(<text x="#{format_num(center_x)}" y="#{format_num(y)}">#{escape_xml(text)}</text>)
      end
    end

    def node_image_line(node)
      return nil unless node_has_image?(node)

      x = node_image_x(node)
      y = node.y + ((node.height - NODE_IMAGE_SIZE) / 2.0)
      href = escape_xml(node.image_path)

      %(<image x="#{format_num(x)}" y="#{format_num(y)}" width="#{format_num(NODE_IMAGE_SIZE)}" height="#{format_num(NODE_IMAGE_SIZE)}" href="#{href}" preserveAspectRatio="xMidYMid slice"/>)
    end

    def node_image_x(node)
      node.x + NODE_IMAGE_MARGIN_LEFT
    end

    def node_has_image?(node)
      return false if node.missing

      image_path = node.image_path.to_s.strip
      !image_path.empty?
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
