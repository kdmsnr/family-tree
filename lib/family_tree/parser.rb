# frozen_string_literal: true

module FamilyTree
  class Parser
    Line = Struct.new(:level, :xref, :tag, :value, :line_no, keyword_init: true)
    ParseState = Struct.new(
      :persons_by_id,
      :families_by_id,
      :warnings,
      :current_record,
      :current_event,
      :auto_person_seq,
      :auto_family_seq,
      keyword_init: true
    )

    def initialize(strict: false)
      @strict = strict
    end

    def parse_text(text)
      state = ParseState.new(
        persons_by_id: {},
        families_by_id: {},
        warnings: [],
        current_record: nil,
        current_event: nil,
        auto_person_seq: 0,
        auto_family_seq: 0
      )

      text.each_line.with_index(1) do |raw_line, line_no|
        next if raw_line.strip.empty?

        line = parse_line(raw_line, line_no)
        if line.level.zero?
          finalize_current_record(state)
          start_record(state, line)
        else
          process_nested_line(state, line)
        end
      end

      finalize_current_record(state)

      result = ParseResult.new(
        persons: state.persons_by_id.values.sort_by(&:id),
        families: state.families_by_id.values.sort_by(&:id),
        warnings: state.warnings.dup
      )

      if @strict && result.warnings.any?
        raise ParseError, "Unsupported GEDCOM tags in strict mode:\n#{result.warnings.join("\n")}"
      end

      result
    end

    private

    def parse_line(raw_line, line_no)
      stripped = raw_line.rstrip
      match = stripped.match(/\A(\d+)\s+(.+)\z/)
      raise ParseError, "Line #{line_no}: invalid GEDCOM line format." unless match

      level = match[1].to_i
      rest = match[2]

      with_xref = rest.match(/\A(@[^@]+@)\s+(\S+)(?:\s+(.*))?\z/)
      without_xref = rest.match(/\A(\S+)(?:\s+(.*))?\z/)

      if with_xref
        Line.new(
          level: level,
          xref: with_xref[1],
          tag: with_xref[2],
          value: with_xref[3],
          line_no: line_no
        )
      elsif without_xref
        Line.new(
          level: level,
          xref: nil,
          tag: without_xref[1],
          value: without_xref[2],
          line_no: line_no
        )
      else
        raise ParseError, "Line #{line_no}: invalid GEDCOM tokens."
      end
    end

    def start_record(state, line)
      state.current_event = nil
      case line.tag
      when "INDI"
        id = normalize_xref(line.xref)
        if id.nil?
          id = next_person_id(state)
          state.warnings << "Line #{line.line_no}: INDI record missing xref, generated #{id}."
        end
        state.current_record = {
          type: :indi,
          line_no: line.line_no,
          data: {
            id: id,
            name: nil,
            sex: nil,
            birth_year: nil,
            death_year: nil
          }
        }
      when "FAM"
        id = normalize_xref(line.xref)
        if id.nil?
          id = next_family_id(state)
          state.warnings << "Line #{line.line_no}: FAM record missing xref, generated #{id}."
        end
        state.current_record = {
          type: :fam,
          line_no: line.line_no,
          data: {
            id: id,
            husband_id: nil,
            wife_id: nil,
            child_ids: []
          }
        }
      else
        state.current_record = nil
      end
    end

    def process_nested_line(state, line)
      return if state.current_record.nil?

      case state.current_record[:type]
      when :indi
        process_indi_line(state, line)
      when :fam
        process_fam_line(state, line)
      end
    end

    def process_indi_line(state, line)
      data = state.current_record[:data]

      if line.level == 1
        state.current_event = nil
        case line.tag
        when "NAME"
          data[:name] = normalize_name(line.value)
        when "SEX"
          sex = line.value.to_s.strip
          data[:sex] = sex.empty? ? nil : sex
        when "BIRT", "DEAT"
          state.current_event = line.tag
        else
          warn_unsupported(state, line, "INDI")
        end
      elsif line.level == 2 && state.current_event
        if line.tag == "DATE"
          year = extract_year(line.value)
          key = (state.current_event == "BIRT") ? :birth_year : :death_year
          data[key] = year if year
        else
          warn_unsupported(state, line, "#{state.current_event}")
        end
      elsif line.level == 2
        warn_unsupported(state, line, "INDI")
      end
    end

    def process_fam_line(state, line)
      return unless line.level == 1

      data = state.current_record[:data]
      case line.tag
      when "HUSB"
        data[:husband_id] = normalize_xref(line.value)
      when "WIFE"
        data[:wife_id] = normalize_xref(line.value)
      when "CHIL"
        id = normalize_xref(line.value)
        data[:child_ids] << id if id
      else
        warn_unsupported(state, line, "FAM")
      end
    end

    def warn_unsupported(state, line, scope)
      state.warnings << "Line #{line.line_no}: unsupported tag '#{line.tag}' in #{scope}."
    end

    def finalize_current_record(state)
      record = state.current_record
      state.current_record = nil
      state.current_event = nil
      return if record.nil?

      case record[:type]
      when :indi
        add_person(state, record[:data], record[:line_no])
      when :fam
        add_family(state, record[:data], record[:line_no])
      end
    end

    def add_person(state, data, line_no)
      id = data[:id]
      if state.persons_by_id.key?(id)
        state.warnings << "Line #{line_no}: duplicate INDI id '#{id}', keeping first record."
        return
      end

      person = Person.new(
        id: id,
        name: data[:name] || id,
        sex: data[:sex],
        birth_year: data[:birth_year],
        death_year: data[:death_year]
      )
      state.persons_by_id[id] = person
    end

    def add_family(state, data, line_no)
      id = data[:id]
      if state.families_by_id.key?(id)
        state.warnings << "Line #{line_no}: duplicate FAM id '#{id}', keeping first record."
        return
      end

      family = Family.new(
        id: id,
        husband_id: data[:husband_id],
        wife_id: data[:wife_id],
        child_ids: data[:child_ids].compact.uniq
      )
      state.families_by_id[id] = family
    end

    def normalize_xref(value)
      return nil if value.nil?

      stripped = value.strip
      return nil if stripped.empty?

      match = stripped.match(/\A@([^@]+)@\z/)
      match ? match[1] : stripped
    end

    def normalize_name(value)
      return nil if value.nil?

      stripped = value.gsub("/", " ").gsub(/\s+/, " ").strip
      stripped.empty? ? nil : stripped
    end

    def extract_year(value)
      return nil if value.nil?

      match = value.match(/(\d{4})/)
      match && match[1]
    end

    def next_person_id(state)
      state.auto_person_seq += 1
      "AUTO_PERSON_#{state.auto_person_seq}"
    end

    def next_family_id(state)
      state.auto_family_seq += 1
      "AUTO_FAMILY_#{state.auto_family_seq}"
    end
  end
end
