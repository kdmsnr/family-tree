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
    MIN_SPOUSE_ROW_VERTICAL_GAP = 24.0
    MIN_SPOUSE_ROW_SPACING_WIDTH = 100.0
    SPOUSE_INNER_OFFSET_RATIO = 0.28
    NODE_INNER_MARGIN = 12.0
    VERTICAL_COLLISION_THRESHOLD = 6.0
    PREFERRED_VERTICAL_CLEARANCE = 22.0
    PREFERRED_HORIZONTAL_CLEARANCE = 20.0
    VERTICAL_CLEARANCE_PENALTY = 20.0
    HORIZONTAL_CLEARANCE_PENALTY = 16.0
    MAX_BRANCH_SHIFT_STEPS = 8
    MAX_LEG_SHIFT_STEPS = 24
    SPOUSE_CROSSING_PENALTY = 64.0
    SPOUSE_EDGE_AVOID_MARGIN = 10.0
    SPOUSE_EDGE_AVOID_PENALTY = 80.0
    CHILD_STROKE_WIDTH = 1.4
    SPOUSE_STROKE_WIDTH = 2.0
    CHILD_HALO_WIDTH = 4.2
    SPOUSE_MULTI_FAMILY_OFFSET_GAP = 10.0
    SPOUSE_SAME_SIDE_FAMILY_OFFSET_GAP = 96.0
    MULTI_MARRIAGE_FAMILY_VERTICAL_GAP = 16.0
    BRIDGE_RADIUS = 4.0
    BRIDGE_CUTOUT_RADIUS = 5.8
    LINE_EPSILON = 0.01
    NODE_IMAGE_SIZE = 36.0
    NODE_IMAGE_MARGIN_LEFT = 8.0
    NODE_TEXT_GAP = 8.0
    NODE_TEXT_RIGHT_MARGIN = 8.0
    SPOUSE_LEG_BEND_DROP = 8.0

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
      occupied_spouse_verticals = []
      occupied_spouse_horizontals = []
      occupied_child_verticals = []
      all_nodes = node_by_id.values
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
      spouse_layout = entries.map do |entry|
        lane_offset = lane_offsets.fetch(entry[:family].id, 0.0)
        family_vertical_offset = family_vertical_offsets.fetch(entry[:family].id, 0.0)
        trunk_x, marriage_y = draw_spouse_section(
          spouse_lines,
          entry[:family].id,
          entry[:spouse_nodes],
          entry[:child_nodes],
          lane_offset,
          spouse_anchor_offsets,
          family_vertical_offset,
          occupied_spouse_verticals,
          occupied_spouse_horizontals,
          all_nodes
        )
        {
          entry: entry,
          lane_offset: lane_offset,
          trunk_x: trunk_x,
          marriage_y: marriage_y
        }
      end

      occupied_child_horizontals = spouse_lines.filter_map { |line| parse_svg_line_segment(line) }
                                            .select { |segment| horizontal_segment?(segment) }
                                            .map do |segment|
        {
          x1: [segment[:x1], segment[:x2]].min,
          x2: [segment[:x1], segment[:x2]].max,
          y: segment[:y1]
        }
      end

      spouse_layout.each do |placement|
        draw_children_section(
          child_lines,
          placement[:trunk_x],
          placement[:marriage_y],
          placement[:entry][:child_nodes],
          placement[:lane_offset],
          occupied_child_verticals,
          occupied_child_horizontals,
          all_nodes
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

        person_center = unique_entries.flat_map { |entry| entry[:spouse_nodes] }
                                     .find { |node| node.id == person_id }
                                     .yield_self { |node| node.nil? ? nil : node_center_x(node) }
        next if person_center.nil?

        sorted_entries = unique_entries.sort_by do |entry|
          family_center_x(entry[:spouse_nodes], entry[:child_nodes])
        end
        center = (sorted_entries.length - 1) / 2.0
        family_centers = sorted_entries.map { |entry| family_center_x(entry[:spouse_nodes], entry[:child_nodes]) }
        all_left = family_centers.all? { |center_x| center_x < (person_center - LINE_EPSILON) }
        all_right = family_centers.all? { |center_x| center_x > (person_center + LINE_EPSILON) }
        offset_gap = if all_left || all_right
                       SPOUSE_SAME_SIDE_FAMILY_OFFSET_GAP
                     else
                       SPOUSE_MULTI_FAMILY_OFFSET_GAP
                     end
        sorted_entries.each_with_index do |entry, index|
          offset = if all_left || all_right
                     (center - index) * offset_gap
                   else
                     (index - center) * offset_gap
                   end
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
        lane_occupancy = []
        prioritized = group.map do |entry|
          left_x, right_x = family_horizontal_span(entry[:spouse_nodes], entry[:child_nodes])
          {
            entry: entry,
            left_x: left_x,
            right_x: right_x,
            width: right_x - left_x,
            center_x: (left_x + right_x) / 2.0
          }
        end.sort_by do |item|
          [
            item[:width],
            item[:center_x],
            item[:entry][:family].id
          ]
        end

        prioritized.each do |item|
          lane_index = 0
          while lane_conflict?(item[:left_x], item[:right_x], lane_occupancy[lane_index])
            lane_index += 1
          end

          lane_occupancy[lane_index] ||= []
          lane_occupancy[lane_index] << [item[:left_x], item[:right_x]]
          offsets[item[:entry][:family].id] = lane_index * EDGE_LANE_GAP
        end
      end
      offsets
    end

    def family_horizontal_span(spouse_nodes, child_nodes)
      anchors = if spouse_nodes.any?
                  spouse_nodes.map { |node| node_center_x(node) }
                else
                  child_nodes.map { |node| node_center_x(node) }
                end
      return [0.0, 0.0] if anchors.empty?

      left_x, right_x = anchors.minmax
      [left_x, right_x]
    end

    def lane_conflict?(left_x, right_x, occupied_ranges)
      return false if occupied_ranges.nil? || occupied_ranges.empty?

      occupied_ranges.any? do |occupied_left_x, occupied_right_x|
        ranges_overlap?(left_x, right_x, occupied_left_x, occupied_right_x)
      end
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

    def draw_spouse_section(
      lines,
      family_id,
      spouse_nodes,
      child_nodes,
      lane_offset,
      spouse_anchor_offsets,
      family_vertical_offset,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
    )
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
        marriage_y = resolve_spouse_marriage_y(
          marriage_y,
          min_marriage_y,
          anchors.first[0],
          anchors.last[0],
          occupied_horizontals
        )
      end

      if anchors.length > 1
        family_center_x = anchors.sum(&:first) / anchors.length.to_f
        routed_anchors = anchors.map do |anchor_x, anchor_y|
          leg_x = resolve_spouse_leg_x(
            anchor_x,
            anchor_y,
            marriage_y,
            family_center_x,
            occupied_verticals,
            occupied_horizontals,
            node_obstacles
          )
          draw_spouse_leg(
            lines,
            anchor_x,
            anchor_y,
            leg_x,
            marriage_y,
            occupied_verticals,
            occupied_horizontals
          )
          [leg_x, anchor_y]
        end
        routed_anchors.sort_by!(&:first)
        lines << svg_line(routed_anchors.first[0], marriage_y, routed_anchors.last[0], marriage_y)
        register_horizontal_segment(occupied_horizontals, routed_anchors.first[0], routed_anchors.last[0], marriage_y)
        trunk_x = routed_anchors.sum(&:first) / routed_anchors.length.to_f
        return [trunk_x, marriage_y]
      else
        anchor_x, anchor_y = anchors.first
        leg_x = resolve_spouse_leg_x(
          anchor_x,
          anchor_y,
          marriage_y,
          anchor_x,
          occupied_verticals,
          occupied_horizontals,
          node_obstacles
        )
        draw_spouse_leg(
          lines,
          anchor_x,
          anchor_y,
          leg_x,
          marriage_y,
          occupied_verticals,
          occupied_horizontals
        )
        return [leg_x, marriage_y]
      end
    end

    def draw_spouse_leg(lines, anchor_x, anchor_y, leg_x, marriage_y, occupied_verticals, occupied_horizontals)
      if (leg_x - anchor_x).abs > 0.5
        bend_y = resolve_spouse_leg_bend_y(anchor_x, leg_x, anchor_y, marriage_y, occupied_horizontals)
        if (bend_y - anchor_y).abs > 0.5
          lines << svg_line(anchor_x, anchor_y, anchor_x, bend_y)
          register_vertical_segment(occupied_verticals, anchor_x, anchor_y, bend_y)
          lines << svg_line(anchor_x, bend_y, leg_x, bend_y)
          register_horizontal_segment(
            occupied_horizontals,
            [anchor_x, leg_x].min,
            [anchor_x, leg_x].max,
            bend_y
          )
          if (marriage_y - bend_y).abs > 0.5
            lines << svg_line(leg_x, bend_y, leg_x, marriage_y)
            register_vertical_segment(occupied_verticals, leg_x, bend_y, marriage_y)
          end
          return
        end
      end

      lines << svg_line(leg_x, anchor_y, leg_x, marriage_y)
      register_vertical_segment(occupied_verticals, leg_x, anchor_y, marriage_y)
    end

    def resolve_spouse_leg_bend_y(anchor_x, leg_x, anchor_y, marriage_y, occupied_horizontals)
      start_y = [anchor_y + SPOUSE_LEG_BEND_DROP, marriage_y].min
      return start_y if (leg_x - anchor_x).abs <= 0.5

      step = [EDGE_LANE_GAP * 0.5, 4.0].max
      min_x = [anchor_x, leg_x].min
      max_x = [anchor_x, leg_x].max
      candidate_y = start_y
      best_candidate_y = nil
      best_score = nil
      while candidate_y <= marriage_y + LINE_EPSILON
        unless horizontal_bus_collision?(min_x, max_x, candidate_y, occupied_horizontals)
          clearance_penalty = horizontal_clearance_penalty(min_x, max_x, candidate_y, occupied_horizontals)
          distance_cost = (candidate_y - start_y).abs * 0.25
          score = clearance_penalty + distance_cost
          if best_score.nil? || score < best_score
            best_score = score
            best_candidate_y = candidate_y
          end
        end

        candidate_y += step
      end

      return best_candidate_y unless best_candidate_y.nil?

      start_y
    end

    def resolve_spouse_marriage_y(desired_y, min_y, left_x, right_x, occupied_horizontals)
      step = [EDGE_LANE_GAP * 0.5, 4.0].max
      base_y = [desired_y, min_y].max
      max_steps = 32
      best_candidate_y = nil
      best_score = nil
      max_steps.times do |step_index|
        offsets = if step_index.zero?
                    [0.0]
                  else
                    # Prefer moving upward first when both sides are equally close.
                    [-(step_index * step), step_index * step]
                  end

        offsets.each do |offset|
          candidate_y = base_y + offset
          next if candidate_y < min_y

          collision = occupied_horizontals.any? do |segment|
            width = segment[:x2] - segment[:x1]
            next false if width < MIN_SPOUSE_ROW_SPACING_WIDTH
            next false unless ranges_overlap?(left_x, right_x, segment[:x1], segment[:x2])

            (segment[:y] - candidate_y).abs < MIN_SPOUSE_ROW_VERTICAL_GAP
          end
          next if collision

          distance_cost = (candidate_y - base_y).abs
          clearance_penalty = horizontal_clearance_penalty(left_x, right_x, candidate_y, occupied_horizontals)
          score = distance_cost + clearance_penalty
          next unless best_score.nil? || score < best_score

          best_score = score
          best_candidate_y = candidate_y
        end
      end

      return best_candidate_y unless best_candidate_y.nil?

      base_y
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

    def draw_children_section(
      lines,
      trunk_x,
      marriage_y,
      child_nodes,
      lane_offset,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
    )
      return if child_nodes.empty?

      child_anchors = child_nodes.map { |node| { x: node_center_x(node), y: node.y } }.sort_by { |anchor| anchor[:x] }
      min_child_y = child_anchors.map { |anchor| anchor[:y] }.min
      desired_sibling_y = marriage_y + SIBLING_GAP + (lane_offset * SIBLING_LANE_OFFSET_FACTOR)
      sibling_y, branch_x = resolve_sibling_geometry(
        trunk_x,
        marriage_y,
        desired_sibling_y,
        min_child_y,
        child_anchors,
        occupied_verticals,
        occupied_horizontals,
        node_obstacles
      )
      child_connectors = child_anchors.map do |child_anchor|
        child_x = child_anchor[:x]
        connector_x = resolve_child_connector_x(
          child_x,
          sibling_y,
          child_anchor[:y],
          branch_x,
          occupied_verticals,
          occupied_horizontals,
          node_obstacles
        )
        child_anchor.merge(connector_x: connector_x)
      end

      branch_start_y = marriage_y
      if (branch_x - trunk_x).abs > 0.5
        branch_turn_y = resolve_branch_turn_y(
          marriage_y,
          sibling_y,
          [trunk_x, branch_x].min,
          [trunk_x, branch_x].max,
          occupied_horizontals
        )
        if (branch_turn_y - marriage_y).abs > 0.5
          lines << svg_line(trunk_x, marriage_y, trunk_x, branch_turn_y)
          register_vertical_segment(occupied_verticals, trunk_x, marriage_y, branch_turn_y)
          lines << svg_line(trunk_x, branch_turn_y, branch_x, branch_turn_y)
          register_horizontal_segment(
            occupied_horizontals,
            [trunk_x, branch_x].min,
            [trunk_x, branch_x].max,
            branch_turn_y
          )
          branch_start_y = branch_turn_y
        else
          lines << svg_line(trunk_x, marriage_y, branch_x, marriage_y)
          register_horizontal_segment(
            occupied_horizontals,
            [trunk_x, branch_x].min,
            [trunk_x, branch_x].max,
            marriage_y
          )
        end
      end

      lines << svg_line(branch_x, branch_start_y, branch_x, sibling_y)
      register_vertical_segment(occupied_verticals, branch_x, branch_start_y, sibling_y)

      if child_connectors.length > 1
        connector_xs = child_connectors.map { |anchor| anchor[:connector_x] } + [branch_x]
        sibling_left_x = connector_xs.min
        sibling_right_x = connector_xs.max
        lines << svg_line(sibling_left_x, sibling_y, sibling_right_x, sibling_y)
        register_horizontal_segment(occupied_horizontals, sibling_left_x, sibling_right_x, sibling_y)
      elsif (branch_x - child_connectors.first[:connector_x]).abs > 0.5
        lines << svg_line(branch_x, sibling_y, child_connectors.first[:connector_x], sibling_y)
        register_horizontal_segment(
          occupied_horizontals,
          [branch_x, child_connectors.first[:connector_x]].min,
          [branch_x, child_connectors.first[:connector_x]].max,
          sibling_y
        )
      end

      child_connectors.each do |child_anchor|
        child_x = child_anchor[:x]
        child_y = child_anchor[:y]
        connector_x = child_anchor[:connector_x]

        lines << svg_line(connector_x, sibling_y, connector_x, child_y)
        register_vertical_segment(occupied_verticals, connector_x, sibling_y, child_y)

        next unless (connector_x - child_x).abs > 0.5

        lines << svg_line(connector_x, child_y, child_x, child_y)
        register_horizontal_segment(
          occupied_horizontals,
          [connector_x, child_x].min,
          [connector_x, child_x].max,
          child_y
        )
      end
    end

    def resolve_sibling_geometry(
      trunk_x,
      marriage_y,
      desired_sibling_y,
      min_child_y,
      child_anchors,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
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
          occupied_verticals,
          occupied_horizontals,
          node_obstacles
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
          occupied_verticals,
          occupied_horizontals,
          node_obstacles
        )
        sibling_left_x = [child_anchors.first[:x], candidate_branch_x].min
        sibling_right_x = [child_anchors.last[:x], candidate_branch_x].max

        collision = child_anchors.any? do |child_anchor|
          vertical_collision?(child_anchor[:x], candidate_y, child_anchor[:y], occupied_verticals)
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
        occupied_verticals,
        occupied_horizontals,
        node_obstacles
      )
      [max_sibling_y, final_branch_x]
    end

    def resolve_branch_turn_y(marriage_y, sibling_y, left_x, right_x, occupied_horizontals)
      step = [EDGE_LANE_GAP * 0.5, 4.0].max
      min_turn_y = marriage_y + step
      max_turn_y = sibling_y - MIN_VERTICAL_GAP
      return marriage_y if max_turn_y <= min_turn_y + LINE_EPSILON

      candidate_y = min_turn_y
      best_candidate_y = nil
      best_score = nil
      while candidate_y <= max_turn_y + LINE_EPSILON
        unless horizontal_bus_collision?(left_x, right_x, candidate_y, occupied_horizontals)
          clearance_penalty = horizontal_clearance_penalty(left_x, right_x, candidate_y, occupied_horizontals)
          distance_cost = (candidate_y - min_turn_y).abs * 0.35
          score = clearance_penalty + distance_cost
          if best_score.nil? || score < best_score
            best_score = score
            best_candidate_y = candidate_y
          end
        end
        candidate_y += step
      end

      return best_candidate_y unless best_candidate_y.nil?

      marriage_y
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

    def resolve_branch_x(
      base_x,
      y1,
      y2,
      child_anchors,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
    )
      child_center_x = child_anchors.sum { |anchor| anchor[:x] } / child_anchors.length
      preferred_direction = child_center_x >= base_x ? 1.0 : -1.0

      candidate_offsets = [0.0]
      1.upto(MAX_BRANCH_SHIFT_STEPS) do |step|
        candidate_offsets << (preferred_direction * EDGE_LANE_GAP * step)
        candidate_offsets << (-preferred_direction * EDGE_LANE_GAP * step)
      end

      best_candidate_x = nil
      best_score = nil
      candidate_offsets.each do |offset|
        candidate_x = base_x + offset
        next if vertical_collision?(candidate_x, y1, y2, occupied_verticals)
        next if vertical_intersects_node?(candidate_x, y1, y2, node_obstacles)

        sibling_left_x = [child_anchors.first[:x], candidate_x].min
        sibling_right_x = [child_anchors.last[:x], candidate_x].max
        next if horizontal_bus_collision?(sibling_left_x, sibling_right_x, y2, occupied_horizontals)

        distance_cost = (candidate_x - base_x).abs
        direction_penalty = preferred_direction * (candidate_x - base_x) >= 0 ? 0.0 : 0.25
        clearance_penalty = vertical_clearance_penalty(candidate_x, y1, y2, occupied_verticals)
        horizontal_penalty = horizontal_clearance_penalty(
          sibling_left_x,
          sibling_right_x,
          y2,
          occupied_horizontals
        )
        score = (distance_cost * 1.5) + direction_penalty + (clearance_penalty * 0.35) + horizontal_penalty
        next unless best_score.nil? || score < best_score

        best_score = score
        best_candidate_x = candidate_x
      end

      return best_candidate_x unless best_candidate_x.nil?

      base_x
    end

    def resolve_child_connector_x(
      child_x,
      sibling_y,
      child_y,
      branch_x,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
    )
      preferred_direction = branch_x <= child_x ? -1.0 : 1.0

      candidate_offsets = [0.0]
      1.upto(MAX_BRANCH_SHIFT_STEPS) do |step|
        candidate_offsets << (preferred_direction * EDGE_LANE_GAP * step)
        candidate_offsets << (-preferred_direction * EDGE_LANE_GAP * step)
      end

      best_candidate_x = nil
      best_score = nil
      candidate_offsets.each do |offset|
        candidate_x = child_x + offset
        next if vertical_collision?(candidate_x, sibling_y, child_y, occupied_verticals)
        next if vertical_intersects_node?(candidate_x, sibling_y, child_y - LINE_EPSILON, node_obstacles)

        horizontal_penalty = 0.0
        if (candidate_x - child_x).abs > 0.5
          horizontal_left_x, horizontal_right_x = [candidate_x, child_x].minmax
          next if horizontal_bus_collision?(horizontal_left_x, horizontal_right_x, child_y, occupied_horizontals)

          horizontal_penalty = horizontal_clearance_penalty(
            horizontal_left_x,
            horizontal_right_x,
            child_y,
            occupied_horizontals
          )
        end

        sibling_horizontal_penalty = 0.0
        if (candidate_x - branch_x).abs > 0.5
          sibling_left_x, sibling_right_x = [candidate_x, branch_x].minmax
          next if horizontal_bus_collision?(sibling_left_x, sibling_right_x, sibling_y, occupied_horizontals)

          sibling_horizontal_penalty = horizontal_clearance_penalty(
            sibling_left_x,
            sibling_right_x,
            sibling_y,
            occupied_horizontals
          )
        end

        distance_cost = (candidate_x - child_x).abs
        direction_penalty = preferred_direction * (candidate_x - child_x) >= 0 ? 0.0 : 0.25
        clearance_penalty = vertical_clearance_penalty(candidate_x, sibling_y, child_y, occupied_verticals)
        score = (distance_cost * 1.2) + direction_penalty + (clearance_penalty * 0.45) + horizontal_penalty + sibling_horizontal_penalty
        next unless best_score.nil? || score < best_score

        best_score = score
        best_candidate_x = candidate_x
      end

      return best_candidate_x unless best_candidate_x.nil?

      child_x
    end

    def resolve_spouse_leg_x(
      base_x,
      y1,
      y2,
      family_center_x,
      occupied_verticals,
      occupied_horizontals,
      node_obstacles
    )
      preferred_direction = base_x < family_center_x ? -1.0 : 1.0
      candidate_offsets = [0.0]
      1.upto(MAX_LEG_SHIFT_STEPS) do |step|
        candidate_offsets << (preferred_direction * EDGE_LANE_GAP * step)
        candidate_offsets << (-preferred_direction * EDGE_LANE_GAP * step)
      end

      best_candidate_x = nil
      best_score = nil
      candidate_offsets.each do |offset|
        candidate_x = base_x + offset
        next if vertical_collision?(candidate_x, y1, y2, occupied_verticals)
        next if vertical_intersects_node?(candidate_x, y1 + LINE_EPSILON, y2 - LINE_EPSILON, node_obstacles)

        crossing_count = vertical_horizontal_cross_count(candidate_x, y1, y2, occupied_horizontals)
        distance_cost = (candidate_x - base_x).abs
        direction_penalty = preferred_direction * (candidate_x - base_x) >= 0 ? 0.0 : 0.25
        clearance_penalty = vertical_clearance_penalty(candidate_x, y1, y2, occupied_verticals)
        edge_penalty = spouse_leg_edge_penalty(candidate_x, y1, y2, node_obstacles)
        score = (crossing_count * SPOUSE_CROSSING_PENALTY) + distance_cost + direction_penalty + clearance_penalty + edge_penalty
        next unless best_score.nil? || score < best_score

        best_score = score
        best_candidate_x = candidate_x
      end

      return best_candidate_x unless best_candidate_x.nil?

      base_x
    end

    def vertical_crosses_horizontals?(x, y1, y2, horizontals)
      min_y, max_y = [y1, y2].minmax
      horizontals.any? do |segment|
        next false unless x > (segment[:x1] + LINE_EPSILON)
        next false unless x < (segment[:x2] - LINE_EPSILON)
        next false unless segment[:y] > (min_y + LINE_EPSILON)
        next false unless segment[:y] < (max_y - LINE_EPSILON)

        true
      end
    end

    def vertical_horizontal_cross_count(x, y1, y2, horizontals)
      min_y, max_y = [y1, y2].minmax
      horizontals.count do |segment|
        next false unless x > (segment[:x1] + LINE_EPSILON)
        next false unless x < (segment[:x2] - LINE_EPSILON)
        next false unless segment[:y] > (min_y + LINE_EPSILON)
        next false unless segment[:y] < (max_y - LINE_EPSILON)

        true
      end
    end

    def spouse_leg_edge_penalty(x, y1, y2, node_obstacles)
      min_y, max_y = [y1, y2].minmax
      node_obstacles.sum(0.0) do |node|
        node_top = node.y + LINE_EPSILON
        node_bottom = node.y + node.height - LINE_EPSILON
        next 0.0 unless max_y > node_top && min_y < node_bottom

        left_distance = (x - node.x).abs
        right_distance = (x - (node.x + node.width)).abs
        edge_distance = [left_distance, right_distance].min
        next 0.0 unless edge_distance < SPOUSE_EDGE_AVOID_MARGIN

        SPOUSE_EDGE_AVOID_PENALTY * (SPOUSE_EDGE_AVOID_MARGIN - edge_distance) / SPOUSE_EDGE_AVOID_MARGIN
      end
    end

    def vertical_clearance_penalty(x, y1, y2, occupied_verticals)
      min_y, max_y = [y1, y2].minmax
      occupied_verticals.sum(0.0) do |segment|
        next 0.0 unless ranges_overlap?(min_y, max_y, segment[:y1], segment[:y2])

        distance = (segment[:x] - x).abs
        next 0.0 if distance >= PREFERRED_VERTICAL_CLEARANCE

        VERTICAL_CLEARANCE_PENALTY * (PREFERRED_VERTICAL_CLEARANCE - distance) / PREFERRED_VERTICAL_CLEARANCE
      end
    end

    def horizontal_clearance_penalty(x1, x2, y, occupied_horizontals)
      occupied_horizontals.sum(0.0) do |segment|
        next 0.0 unless ranges_overlap?(x1, x2, segment[:x1], segment[:x2])

        distance = (segment[:y] - y).abs
        next 0.0 if distance >= PREFERRED_HORIZONTAL_CLEARANCE

        HORIZONTAL_CLEARANCE_PENALTY * (PREFERRED_HORIZONTAL_CLEARANCE - distance) / PREFERRED_HORIZONTAL_CLEARANCE
      end
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

    def vertical_intersects_node?(x, y1, y2, nodes)
      segment_top, segment_bottom = [y1, y2].minmax

      nodes.any? do |node|
        node_left = node.x + LINE_EPSILON
        node_right = node.x + node.width - LINE_EPSILON
        next false unless x > node_left && x < node_right

        node_top = node.y + LINE_EPSILON
        node_bottom = node.y + node.height - LINE_EPSILON
        segment_top < node_bottom && segment_bottom > node_top
      end
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
