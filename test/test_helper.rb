# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "family_tree"

module TestSupport
  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def cli_path
    File.expand_path("../bin/family-tree", __dir__)
  end
end

class Minitest::Test
  include TestSupport
end
