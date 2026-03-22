# frozen_string_literal: true

# This migration comes from rails_error_dashboard (originally 20260307000001)
class CreateRailsErrorDashboardDiagnosticDumps < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_error_dashboard_diagnostic_dumps do |t|
      t.references :application, null: false,
        foreign_key: { to_table: :rails_error_dashboard_applications }
      t.text :dump_data, null: false
      t.string :note
      t.datetime :captured_at, null: false
      t.timestamps
    end

    add_index :rails_error_dashboard_diagnostic_dumps, :captured_at,
              name: "index_diagnostic_dumps_on_captured_at"
  end
end
