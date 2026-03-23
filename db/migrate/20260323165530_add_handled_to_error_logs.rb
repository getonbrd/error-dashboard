class AddHandledToErrorLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :rails_error_dashboard_error_logs, :handled, :boolean
  end
end
