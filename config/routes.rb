Rails.application.routes.draw do
  mount RailsErrorDashboard::Engine, at: "/error_dashboard"

  namespace :api do
    namespace :v1 do
      resources :errors, only: [ :index, :show, :create ] do
        collection do
          post :batch
        end
      end
    end
  end

  get "health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check
end
