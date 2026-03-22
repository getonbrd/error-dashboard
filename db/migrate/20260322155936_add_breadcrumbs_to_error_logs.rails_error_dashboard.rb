# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260303000001)
class AddBreadcrumbsToErrorLogs < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_error_dashboard_error_logs, :breadcrumbs)
      add_column :rails_error_dashboard_error_logs, :breadcrumbs, :text
    end
  end
end
