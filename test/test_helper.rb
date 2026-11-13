# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rubytofaster"
require "minitest/autorun"
require "fileutils"
require "json"
require "tmpdir"
