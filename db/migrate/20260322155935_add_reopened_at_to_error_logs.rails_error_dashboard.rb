# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260221000002)
class AddReopenedAtToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_error_dashboard_error_logs, :reopened_at)
      add_column :rails_error_dashboard_error_logs, :reopened_at, :datetime
    end
  end
end
