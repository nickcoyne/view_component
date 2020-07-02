# frozen_string_literal: true

require "rails"
require "view_component"

module ViewComponent
  class Engine < Rails::Engine # :nodoc:
    config.view_component = ActiveSupport::OrderedOptions.new

    initializer "view_component.set_configs" do |app|
      options = app.config.view_component

      options.render_monkey_patch_enabled = true if options.render_monkey_patch_enabled.nil?
      options.show_previews = Rails.env.development? if options.show_previews.nil?
      options.preview_route ||= ViewComponent::Base.preview_route

      if options.show_previews
        options.preview_path ||= defined?(Rails.root) ? "#{Rails.root}/test/components/previews" : nil
      end

      ActiveSupport.on_load(:view_component) do
        options.each { |k, v| send("#{k}=", v) }
      end
    end

    initializer "view_component.set_autoload_paths" do |app|
      options = app.config.view_component

      if options.show_previews && options.preview_path
        ActiveSupport::Dependencies.autoload_paths << options.preview_path
      end
    end

    initializer "view_component.eager_load_actions" do
      ActiveSupport.on_load(:after_initialize) do
        ViewComponent::Base.descendants.each(&:compile)
      end
    end

    initializer "view_component.compile_config_methods" do
      ActiveSupport.on_load(:view_component) do
        config.compile_methods! if config.respond_to?(:compile_methods!)
      end
    end

    initializer "view_component.monkey_patch_render" do |app|
      next if Rails.version.to_f >= 6.1 || !app.config.view_component.render_monkey_patch_enabled

      ActiveSupport.on_load(:action_view) do
        require "view_component/render_monkey_patch"
        ActionView::Base.prepend ViewComponent::RenderMonkeyPatch
      end

      ActiveSupport.on_load(:action_controller) do
        require "view_component/rendering_monkey_patch"
        require "view_component/render_to_string_monkey_patch"
        ActionController::Base.prepend ViewComponent::RenderingMonkeyPatch
        ActionController::Base.prepend ViewComponent::RenderToStringMonkeyPatch
      end
    end

    initializer "view_component.include_render_component" do |app|
      next if Rails.version.to_f >= 6.1

      ActiveSupport.on_load(:action_view) do
        require "view_component/render_component_helper"
        ActionView::Base.include ViewComponent::RenderComponentHelper
      end

      ActiveSupport.on_load(:action_controller) do
        require "view_component/rendering_component_helper"
        require "view_component/render_component_to_string_helper"
        ActionController::Base.include ViewComponent::RenderingComponentHelper
        ActionController::Base.include ViewComponent::RenderComponentToStringHelper
      end
    end

    config.after_initialize do |app|
      options = app.config.view_component

      if options.show_previews
        app.routes.prepend do
          get options.preview_route, to: "view_components#index", as: :preview_view_components, internal: true
          get "#{options.preview_route}/*path", to: "view_components#previews", as: :preview_view_component, internal: true
        end
      end

      app.executor.to_run :before do
        CompileCache.invalidate! unless ActionView::Base.cache_template_loading
      end
    end
  end
end
