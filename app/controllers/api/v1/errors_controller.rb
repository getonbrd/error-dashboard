module Api
  module V1
    class ErrorsController < ApplicationController
      skip_forgery_protection

      before_action :authenticate_bearer_token!

      def create
        result = report_error(error_params)

        if result
          render json: { id: result.id }, status: :created
        else
          render json: { error: "Failed to log error" }, status: :unprocessable_entity
        end
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
          metadata: permitted_params[:metadata]&.to_h,
          occurred_at: permitted_params[:occurred_at],
          severity: permitted_params[:severity]&.to_sym,
          source: permitted_params[:source]
        )
      end
    end
  end
end
