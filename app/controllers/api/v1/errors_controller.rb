module Api
  module V1
    class ErrorsController < ApplicationController
      skip_forgery_protection

      before_action :authenticate_bearer_token!

      def index
        errors = RailsErrorDashboard::ErrorLog.order(occurred_at: :desc)
        errors = errors.where(error_type: params[:error_type]) if params[:error_type].present?
        errors = errors.where(platform: params[:platform]) if params[:platform].present?
        errors = errors.where(resolved: params[:resolved] == "true") if params[:resolved].present?
        errors = errors.where(priority_level: params[:priority_level]) if params[:priority_level].present?

        page = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 25).to_i, 100].min
        total = errors.count
        errors = errors.offset((page - 1) * per_page).limit(per_page)

        render json: {
          errors: errors.map { |e| serialize_error(e) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      def show
        error = RailsErrorDashboard::ErrorLog.find(params[:id])
        render json: { error: serialize_error(error, detailed: true) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def create
        report_error(error_params)
        render json: { status: "accepted" }, status: :created
      end

      def batch
        results = Array(params[:errors]).map { |e| report_error(e.permit!) }
        logged = results.compact.size

        render json: { logged: logged, total: Array(params[:errors]).size }, status: :created
      end

      private

      def authenticate_bearer_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, ENV.fetch("API_BEARER_TOKEN"))
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def error_params
        params.require(:error).permit(
          :error_type, :message, :severity, :platform, :source,
          :app_version, :user_id, :request_url, :ip_address,
          :user_agent, :occurred_at,
          backtrace: [], metadata: {}
        )
      end

      def serialize_error(error, detailed: false)
        data = {
          id: error.id,
          error_type: error.error_type,
          message: error.message,
          platform: error.platform,
          app_version: error.app_version,
          user_id: error.user_id,
          request_url: error.request_url,
          resolved: error.resolved,
          occurrence_count: error.occurrence_count,
          first_seen_at: error.first_seen_at,
          last_seen_at: error.last_seen_at,
          occurred_at: error.occurred_at
        }

        if detailed
          data[:backtrace] = error.backtrace
          data[:ip_address] = error.ip_address
          data[:user_agent] = error.user_agent
          data[:request_params] = error.request_params
          data[:git_sha] = error.git_sha
        end

        data
      end

      def report_error(permitted_params)
        RailsErrorDashboard::ManualErrorReporter.report(
          error_type: permitted_params[:error_type],
          message: permitted_params[:message],
          backtrace: permitted_params[:backtrace],
          platform: permitted_params[:platform],
          user_id: permitted_params[:user_id],
          request_url: permitted_params[:request_url],
          user_agent: permitted_params[:user_agent],
          ip_address: permitted_params[:ip_address],
          app_version: permitted_params[:app_version],
          metadata: sanitize_metadata(permitted_params[:metadata]),
          occurred_at: permitted_params[:occurred_at],
          severity: permitted_params[:severity]&.to_sym,
          source: permitted_params[:source]
        )
      end

      def sanitize_metadata(metadata)
        return nil if metadata.blank?

        metadata.to_unsafe_h.to_json
      end
    end
  end
end
