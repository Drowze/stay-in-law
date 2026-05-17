require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

Dotenv.load(".env.#{ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", "development"))}", ".env")

module StayInLaw
  class Application < Rails::Application
    config.load_defaults 7.2
    config.autoload_lib(ignore: %w[assets tasks])
    config.time_zone = "UTC"
    config.generators.system_tests = nil
  end
end
