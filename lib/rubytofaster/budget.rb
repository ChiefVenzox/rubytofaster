# frozen_string_literal: true

module RubyToFaster
  # Angular-inspired package and asset size budget evaluator.
  class BudgetEvaluator
    def initialize(budgets)
      @budgets = Array(budgets)
    end

    def evaluate!(compressed_bytes:, unpacked_bytes:, entry_sizes:)
      warnings = []
      errors   = []

      compressed_kb = compressed_bytes / 1024.0
      unpacked_kb   = unpacked_bytes / 1024.0

      @budgets.each do |rule|
        warn_ratio = rule[:warn_ratio] || 0.85

        if rule[:max_compressed_kb]
          limit = rule[:max_compressed_kb].to_f
          if compressed_kb > limit
            errors << format("Compressed .gem size (%.2f KB) exceeds budget (%.2f KB)", compressed_kb, limit)
          elsif compressed_kb >= limit * warn_ratio
            warnings << format("Compressed .gem size (%.2f KB) is approaching budget (%.2f KB)", compressed_kb, limit)
          end
        end

        if rule[:max_unpacked_kb]
          limit = rule[:max_unpacked_kb].to_f
          if unpacked_kb > limit
            errors << format("Unpacked payload size (%.2f KB) exceeds budget (%.2f KB)", unpacked_kb, limit)
          elsif unpacked_kb >= limit * warn_ratio
            warnings << format("Unpacked payload size (%.2f KB) is approaching budget (%.2f KB)", unpacked_kb, limit)
          end
        end

        next unless rule[:max_entry_kb]

        entry_limit = rule[:max_entry_kb].to_f
        entry_sizes.each do |gem_path, bytes|
          kb = bytes / 1024.0
          if kb > entry_limit
            errors << format("Entry '%s' (%.2f KB) exceeds max_entry_kb budget (%.2f KB)", gem_path, kb, entry_limit)
          elsif kb >= entry_limit * warn_ratio
            warnings << format("Entry '%s' (%.2f KB) is approaching max_entry_kb budget (%.2f KB)", gem_path, kb, entry_limit)
          end
        end
      end

      unless errors.empty?
        raise BudgetExceededError, "Package size budget exceeded:\n  - #{errors.join("\n  - ")}"
      end

      warnings
    end
  end
end
