# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260306000002)
class AddInstanceVariablesToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_error_dashboard_error_logs, :instance_variables, :text
  end
end
