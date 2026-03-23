class AddUserTypeToErrorLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :rails_error_dashboard_error_logs, :user_type, :string
  end
end
