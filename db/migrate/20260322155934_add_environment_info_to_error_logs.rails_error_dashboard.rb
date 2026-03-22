# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260221000001)
class AddEnvironmentInfoToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_error_dashboard_error_logs, :environment_info)
      add_column :rails_error_dashboard_error_logs, :environment_info, :text
    end
  end
end
