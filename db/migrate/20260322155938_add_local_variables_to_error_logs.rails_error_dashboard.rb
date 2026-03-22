# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260306000001)
class AddLocalVariablesToErrorLogs < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:rails_error_dashboard_error_logs, :local_variables)

    add_column :rails_error_dashboard_error_logs, :local_variables, :text
  end

  def down
    remove_column :rails_error_dashboard_error_logs, :local_variables if column_exists?(:rails_error_dashboard_error_logs, :local_variables)
  end
end
