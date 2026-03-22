# This migration comes from rails_error_dashboard (originally 20260106094220)
class CreateRailsErrorDashboardApplications < ActiveRecord::Migration[7.0]
  def change
    # Skip if squashed migration already ran (applications table already exists)
    return if table_exists?(:rails_error_dashboard_applications)

    create_table :rails_error_dashboard_applications do |t|
      t.string :name, null: false, limit: 255
      t.text :description

      t.timestamps
    end

    # Unique constraint - app names must be unique
    add_index :rails_error_dashboard_applications, :name, unique: true
  end
end
