# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def test_render_writes_svg
    Dir.mktmpdir do |tmp_dir|
      output = File.join(tmp_dir, "tree.svg")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        cli_path,
        "render",
        fixture_path("basic.ged"),
        "-o",
        output
      )

      assert status.success?, "stderr: #{stderr}"
      assert_includes stdout, "Wrote #{output}"
      assert File.exist?(output)
      assert_includes File.read(output), "<svg"
    end
  end

  def test_render_writes_svg_from_simple_format
    Dir.mktmpdir do |tmp_dir|
      output = File.join(tmp_dir, "tree.svg")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        cli_path,
        "render",
        fixture_path("simple.ftree"),
        "-o",
        output
      )

      assert status.success?, "stderr: #{stderr}"
      assert_includes stdout, "Wrote #{output}"
      assert File.exist?(output)
      assert_includes File.read(output), "<svg"
      assert_includes File.read(output), "Taro Yamada"
    end
  end

  def test_render_fails_in_strict_mode_when_unsupported_tags_exist
    Dir.mktmpdir do |tmp_dir|
      output = File.join(tmp_dir, "tree.svg")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        cli_path,
        "render",
        fixture_path("unknown_tag.ged"),
        "-o",
        output,
        "--strict"
      )

      refute status.success?
      assert_equal "", stdout
      assert_includes stderr, "strict mode"
      refute File.exist?(output)
    end
  end

  def test_render_requires_output_option
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      cli_path,
      "render",
      fixture_path("basic.ged")
    )

    refute status.success?
    assert_includes stderr, "OUTPUT.svg is required"
  end

  def test_render_fails_for_unknown_format_option
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      cli_path,
      "render",
      fixture_path("simple.ftree"),
      "-o",
      File.join(Dir.tmpdir, "tree.svg"),
      "--format",
      "yaml"
    )

    refute status.success?
    assert_includes stderr, "Unknown input format"
  end
end
