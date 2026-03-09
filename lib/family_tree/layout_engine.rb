# frozen_string_literal: true

module FamilyTree
  class LayoutEngine
    DEFAULT_METRICS = {
      node_width: 156.0,
      node_height: 60.0,
      node_gap: 56.0,
      level_gap: 120.0,
      margin_left: 48.0,
      margin_top: 48.0,
      margin_right: 48.0,
      margin_bottom: 72.0,
      connector_padding: 40.0
    }.freeze

    UnionFind = Struct.new(:parent, :size, keyword_init: true) do
      def self.from_elements(elements)
        parent = {}
        size = {}
        elements.each do |element|
          parent[element] = element
          size[element] = 1
        end
        new(parent: parent, size: size)
      end

      def find(element)
        root = element
        root = parent[root] while parent[root] != root
        while element != root
          next_element = parent[element]
          parent[element] = root
          element = next_element
        end
        root
      end

      def union(left, right)
        left_root = find(left)
        right_root = find(right)
        return if left_root == right_root

        if size[left_root] < size[right_root]
          left_root, right_root = right_root, left_root
        end

        parent[right_root] = left_root
        size[left_root] += size[right_root]
      end
    end

    def initialize(metrics = {})
      @metrics = DEFAULT_METRICS.merge(metrics)
    end

    def layout(parse_result)
      persons = parse_result.persons.sort_by(&:id)
      families = parse_result.families.sort_by(&:id)
      person_by_id = persons.each_with_object({}) { |person, acc| acc[person.id] = person }
      missing_ids = referenced_person_ids(families) - person_by_id.keys
      all_person_ids = (person_by_id.keys + missing_ids).uniq.sort

      generation = compute_generation_levels(all_person_ids, families)
      order_by_level = order_by_generation(all_person_ids, generation, person_by_id, families)
      x_center = x_centers(order_by_level)
      level_values = generation.values
      min_level = level_values.min || 0

      nodes = all_person_ids.map do |person_id|
        person = person_by_id[person_id]
        level = generation.fetch(person_id, 0)
        normalized_level = level - min_level
        center_x = x_center.fetch(person_id)
        center_y = @metrics[:margin_top] + normalized_level * (@metrics[:node_height] + @metrics[:level_gap]) + (@metrics[:node_height] / 2.0)

        LayoutNode.new(
          id: person_id,
          label: person_label(person, person_id),
          x: center_x - (@metrics[:node_width] / 2.0),
          y: center_y - (@metrics[:node_height] / 2.0),
          width: @metrics[:node_width],
          height: @metrics[:node_height],
          missing: person.nil?,
          image_path: person&.image_path
        )
      end

      node_by_id = nodes.each_with_object({}) { |node, acc| acc[node.id] = node }

      layout_families = families.map do |family|
        LayoutFamily.new(
          id: family.id,
          spouse_ids: [family.husband_id, family.wife_id].compact.uniq,
          child_ids: family.child_ids.compact.uniq
        )
      end

      align_single_child_nodes!(node_by_id, layout_families)
      nodes = node_by_id.values.sort_by(&:id)

      max_right = nodes.map { |node| node.x + node.width }.max || 0.0
      max_bottom = nodes.map { |node| node.y + node.height }.max || 0.0

      LayoutResult.new(
        nodes: nodes.sort_by(&:id),
        families: layout_families.sort_by(&:id),
        canvas_width: (max_right + @metrics[:margin_right]).ceil,
        canvas_height: (max_bottom + @metrics[:margin_bottom] + @metrics[:connector_padding]).ceil
      )
    end

    private

    def align_single_child_nodes!(node_by_id, layout_families)
      candidates = []
      layout_families.each do |family|
        child_ids = family.child_ids.compact.uniq
        next unless child_ids.length == 1

        child_node = node_by_id[child_ids.first]
        next if child_node.nil?

        spouse_nodes = family.spouse_ids.filter_map { |person_id| node_by_id[person_id] }
        next if spouse_nodes.empty?

        target_center_x = spouse_nodes.sum { |node| node_center_x(node) } / spouse_nodes.length.to_f
        candidates << {
          child_id: child_node.id,
          y: child_node.y,
          width: child_node.width,
          original_x: child_node.x,
          target_center_x: target_center_x
        }
      end

      return if candidates.empty?

      candidate_ids = candidates.map { |entry| entry[:child_id] }.to_h { |id| [id, true] }
      fixed_nodes = node_by_id.values.reject { |node| candidate_ids[node.id] }
      accepted = []

      candidates
        .sort_by { |entry| [entry[:y], entry[:target_center_x], entry[:child_id]] }
        .each do |entry|
          next if center_conflict?(entry, fixed_nodes, accepted)

          accepted << entry
        end

      accepted.each do |entry|
        child_node = node_by_id[entry[:child_id]]
        child_node.x = entry[:target_center_x] - (child_node.width / 2.0)
      end

      revert_overlapping_centered_nodes!(node_by_id, accepted)
    end

    def center_conflict?(entry, fixed_nodes, accepted_candidates)
      min_center_gap = entry[:width] + (@metrics[:node_gap] * 0.35)

      fixed_nodes.each do |node|
        next unless (node.y - entry[:y]).abs <= 0.01

        return true if (node_center_x(node) - entry[:target_center_x]).abs < min_center_gap
      end

      accepted_candidates.each do |accepted|
        next unless (accepted[:y] - entry[:y]).abs <= 0.01

        return true if (accepted[:target_center_x] - entry[:target_center_x]).abs < min_center_gap
      end

      false
    end

    def revert_overlapping_centered_nodes!(node_by_id, accepted_candidates)
      accepted_candidates.each do |entry|
        child_node = node_by_id[entry[:child_id]]
        next if child_node.nil?
        next unless row_overlap?(child_node, node_by_id.values)

        child_node.x = entry[:original_x]
      end
    end

    def row_overlap?(node, all_nodes)
      min_center_gap = node.width + (@metrics[:node_gap] * 0.35)
      node_center = node_center_x(node)

      all_nodes.any? do |other_node|
        next false if other_node.id == node.id
        next false unless (other_node.y - node.y).abs <= 0.01

        (node_center_x(other_node) - node_center).abs < min_center_gap
      end
    end

    def node_center_x(node)
      node.x + (node.width / 2.0)
    end

    def referenced_person_ids(families)
      families.flat_map { |family| [family.husband_id, family.wife_id, *family.child_ids] }.compact.uniq
    end

    def compute_generation_levels(person_ids, families)
      return {} if person_ids.empty?

      union_find = UnionFind.from_elements(person_ids)
      families.each do |family|
        spouses = [family.husband_id, family.wife_id].compact.uniq
        spouses.each_cons(2) { |left, right| union_find.union(left, right) }
      end

      constraints = []
      families.each do |family|
        parent_ids = [family.husband_id, family.wife_id].compact.uniq
        child_ids = family.child_ids.compact.uniq
        next if parent_ids.empty? || child_ids.empty?

        parent_groups = parent_ids.map { |person_id| union_find.find(person_id) }.uniq
        child_groups = child_ids.map { |person_id| union_find.find(person_id) }.uniq

        parent_groups.each do |parent_group|
          child_groups.each do |child_group|
            next if parent_group == child_group

            constraints << [parent_group, child_group]
          end
        end
      end
      constraints.uniq!

      group_level = Hash.new(0)
      max_iterations = [person_ids.length * person_ids.length, 1].max
      max_iterations.times do
        changed = false
        constraints.each do |parent_group, child_group|
          target_level = group_level[parent_group] + 1
          next unless target_level > group_level[child_group]

          group_level[child_group] = target_level
          changed = true
        end
        break unless changed
      end

      person_ids.each_with_object({}) do |person_id, levels|
        levels[person_id] = group_level[union_find.find(person_id)]
      end
    end

    def order_by_generation(person_ids, generation, person_by_id, families)
      level_map = Hash.new { |hash, key| hash[key] = [] }
      person_ids.each { |person_id| level_map[generation.fetch(person_id, 0)] << person_id }
      levels = level_map.keys.sort

      order = {}
      levels.each do |level|
        order[level] = level_map[level].sort_by { |person_id| person_sort_key(person_by_id[person_id], person_id) }
      end

      child_to_families = Hash.new { |hash, key| hash[key] = [] }
      parent_to_families = Hash.new { |hash, key| hash[key] = [] }
      families.each do |family|
        family.child_ids.each { |child_id| child_to_families[child_id] << family }
        [family.husband_id, family.wife_id].compact.each { |parent_id| parent_to_families[parent_id] << family }
      end

      3.times do
        levels.each do |level|
          next if level == levels.first

          index_map = position_index_map(order)
          sorted = order[level].sort_by do |person_id|
            [
              parent_barycenter(person_id, child_to_families, index_map),
              person_sort_key(person_by_id[person_id], person_id)
            ]
          end
          order[level] = apply_level_constraints(sorted, families, generation, level, index_map)
        end

        levels.reverse_each do |level|
          next if level == levels.last

          index_map = position_index_map(order)
          sorted = order[level].sort_by do |person_id|
            [
              child_barycenter(person_id, parent_to_families, index_map),
              person_sort_key(person_by_id[person_id], person_id)
            ]
          end
          order[level] = apply_level_constraints(sorted, families, generation, level, index_map)
        end
      end

      order
    end

    def position_index_map(order_by_level)
      index_map = {}
      order_by_level.each_value do |ids|
        ids.each_with_index { |person_id, idx| index_map[person_id] = idx }
      end
      index_map
    end

    def parent_barycenter(person_id, child_to_families, index_map)
      families = child_to_families[person_id]
      return Float::INFINITY if families.empty?

      parent_indices = families
        .flat_map { |family| [family.husband_id, family.wife_id] }
        .compact
        .filter_map { |parent_id| index_map[parent_id] }

      return Float::INFINITY if parent_indices.empty?

      parent_indices.sum.to_f / parent_indices.length
    end

    def child_barycenter(person_id, parent_to_families, index_map)
      families = parent_to_families[person_id]
      return Float::INFINITY if families.empty?

      child_indices = families
        .flat_map(&:child_ids)
        .compact
        .filter_map { |child_id| index_map[child_id] }

      return Float::INFINITY if child_indices.empty?

      child_indices.sum.to_f / child_indices.length
    end

    def apply_level_constraints(ids, families, generation, level, index_map)
      constrained = ids.dup
      constrained = enforce_spouse_adjacency(constrained, families, generation, level)
      constrained = enforce_sibling_blocks(constrained, families, generation, level, index_map)
      constrained
    end

    def enforce_spouse_adjacency(ids, families, generation, level)
      ordered = ids.dup
      families.each do |family|
        spouses = [family.husband_id, family.wife_id].compact.uniq
        next unless spouses.length == 2
        next unless spouses.all? { |person_id| generation.fetch(person_id, -1) == level }
        next unless spouses.all? { |person_id| ordered.include?(person_id) }

        ordered = make_adjacent(ordered, spouses[0], spouses[1])
      end
      ordered
    end

    def enforce_sibling_blocks(ids, families, generation, level, _index_map)
      ordered = ids.dup
      sibling_groups = families.map do |family|
        group = family.child_ids.compact.uniq.select { |child_id| generation.fetch(child_id, -1) == level }
        group.length > 1 ? group : nil
      end.compact

      sibling_groups.each do |group|
        present = group.select { |person_id| ordered.include?(person_id) }
        next if present.length < 2

        start_index = present.map { |person_id| ordered.index(person_id) }.min
        ordered -= present
        ordered.insert(start_index, *present)
      end

      ordered
    end

    def make_adjacent(ids, left_id, right_id)
      ordered = ids.dup
      left_index = ordered.index(left_id)
      right_index = ordered.index(right_id)
      return ordered if left_index.nil? || right_index.nil?
      return ordered if (left_index - right_index).abs == 1

      if left_index < right_index
        ordered.delete_at(right_index)
        ordered.insert(left_index + 1, right_id)
      else
        ordered.delete_at(left_index)
        ordered.insert(right_index + 1, left_id)
      end

      ordered
    end

    def x_centers(order_by_level)
      slot_width = @metrics[:node_width] + @metrics[:node_gap]

      x_map = {}
      order_by_level.each_value do |ids|
        ids.each_with_index do |person_id, index|
          x_map[person_id] = @metrics[:margin_left] + index * slot_width + (@metrics[:node_width] / 2.0)
        end
      end
      x_map
    end

    def person_label(person, fallback_id)
      return fallback_id if person.nil?

      name = person.name.to_s.strip
      name = fallback_id if name.empty?
      birth = person.birth_year
      death = person.death_year
      return name if birth.nil? && death.nil?

      "#{name}\n#{birth || "?"}-#{death || "?"}"
    end

    def person_sort_key(person, person_id)
      return [9_999, person_id] if person.nil?

      birth_year = person.birth_year.to_i
      birth_year = 9_999 if birth_year.zero?
      [birth_year, person_id]
    end
  end
end
