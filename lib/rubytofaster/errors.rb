# frozen_string_literal: true

module RubyToFaster
  # Base error class for all RubyToFaster exceptions.
  class Error < StandardError; end

  # Raised when a build script, gemspec, or resource configuration is invalid.
  class ConfigError < Error; end

  # Raised when native compilation, frontend resource bundling, or packaging fails.
  class BuildError < Error; end

  # Raised when package or resource sizes exceed configured Angular-style budgets.
  class BudgetExceededError < BuildError; end

  # Raised when path traversal, unsafe symlinks, or secret leakage is detected.
  class SecurityError < Error; end
end
