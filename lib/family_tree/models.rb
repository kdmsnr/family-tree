# frozen_string_literal: true

module FamilyTree
  ParseError = Class.new(StandardError)
  RenderError = Class.new(StandardError)

  Person = Struct.new(
    :id,
    :name,
    :sex,
    :birth_year,
    :death_year,
    :image_path,
    keyword_init: true
  )

  Family = Struct.new(
    :id,
    :husband_id,
    :wife_id,
    :child_ids,
    keyword_init: true
  )

  ParseResult = Struct.new(
    :persons,
    :families,
    :warnings,
    keyword_init: true
  )

  LayoutNode = Struct.new(
    :id,
    :label,
    :x,
    :y,
    :width,
    :height,
    :missing,
    :image_path,
    keyword_init: true
  )

  LayoutFamily = Struct.new(
    :id,
    :spouse_ids,
    :child_ids,
    keyword_init: true
  )

  LayoutResult = Struct.new(
    :nodes,
    :families,
    :canvas_width,
    :canvas_height,
    keyword_init: true
  )
end
