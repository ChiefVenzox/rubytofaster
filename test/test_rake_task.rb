# frozen_string_literal: true

require "test_helper"
require "rubytofaster/rake_task"

class TestRakeTask < Minitest::Test
  def test_rake_task_defines_expected_tasks
    Rake::Task.clear
    RubyToFaster::RakeTask.new(:build_gem) do |t|
      t.out_dir = "pkg_rake"
      t.incremental = true
    end

    assert Rake::Task.task_defined?("build_gem"), "Expected :build_gem to be defined"
    assert Rake::Task.task_defined?("rtf:build"), "Expected 'rtf:build' to be defined"
    assert Rake::Task.task_defined?("rtf:clean"), "Expected 'rtf:clean' to be defined"
    assert Rake::Task.task_defined?("rtf:check"), "Expected 'rtf:check' to be defined"
    assert Rake::Task.task_defined?("rtf:bench"), "Expected 'rtf:bench' to be defined"
    assert Rake::Task.task_defined?("rtf:install"), "Expected 'rtf:install' to be defined"
  end
end
