# How to utilize CanCan Permissions to work with this controller:
module CanCanCan
  module AbstractResourceController
    extend ActiveSupport::Concern

    included do
      before_action :initialize_resource_class
    end

    # Used to stop infinite recursive on associations (could just be deeply nested structures. Could also be self-referencing).
    MAX_ASSOCIATIVE_NESTED_DEPTH = 60
    REGEX_FOR_HTML_TAG_DETECTION = /.*\<\/?[^_\W]+\>.*/

    # to handle adding/removing associations by "_ids" suffix
    IDS_ATTIB_PERMISSION_KEY_GEN = Proc.new { |assoc_key| "#{assoc_key.to_s.singularize}_ids".to_sym }
    IDS_ACTION_PERMISSION_KEY_GEN = Proc.new { |assoc_key| "_can_add_or_remove_association_#{assoc_key.to_s}".to_sym }

    # to handle updating nested attributes
    NESTED_ATTIB_PERMISSION_KEY_GEN = Proc.new { |assoc_key| "#{assoc_key.to_s}_attributes".to_sym }
    NESTED_ACTION_PERMISSION_KEY_GEN  = Proc.new { |assoc_key| "_can_update_association_#{assoc_key.to_s}".to_sym }

    # For Read-Only fields
    #  - define this on your class model
    # optional allowlist for incoming parameters for the implemented resource
    # - nil means allowlist is inactive, acceptable parameters are determined by cancan attrib permissions
    # - [] (empty array) means that no parameters will be accepted for resource
    # - [<param1>, <param2>, ...] is self-explanatory, only those listed will be accepted
    # class Resource
    #   RESOURCE_CONTROLLER_ATTRIB_ALLOWLIST = nil
    # end

    # probably a better way to do this. If there is, it's poorly documented.
    # - src: https://www.w3schools.com/TAGS/default.ASP
    # DEFAULT_PARAMETER_SANITIZER_ALLOWED_TAGS    -  Add to this env var any values to also allow for HTML tags (i.e.: label,span,text_area)
    # DEFAULT_PARAMETER_SANITIZER_ALLOWED_ATTRIBS - Add to this env var any values to also allow for HTML attribs (i.e.: ng-show,ng-hide,data-id)
    DEFAULT_PARAMETER_SANITIZER_ALLOWED_TAGS = (
        %w[
        p
        div
        span
        body
        b
        strong
        br
        center
        font
        label
        pre
        tr
        td
        table
        text_area
        ul
        li
        footer
        em
        ol
        i
        select
        option
      ] + (ENV['DEFAULT_PARAMETER_SANITIZER_ALLOWED_TAGS']&.split(',')&.collect(&:strip) || [])
    ).freeze
    # Only allow attribs that are allowed in HTML friendly text blocks
    # - i.e. NO HREFs!
    DEFAULT_PARAMETER_SANITIZER_ALLOWED_ATTRIBS = (
        %w[
        style
        id
        class
        type
        value
      ] + (ENV['DEFAULT_PARAMETER_SANITIZER_ALLOWED_ATTRIBS']&.split(',')&.collect(&:strip) || [])
    ).freeze

    def index
      authorize! :index, @resource_class
      @resources ||= @resource_class

      begin
        @resources = @resources.accessible_by(current_ability)
      rescue CanCan::Error => e
        # The accessible_by call cannot be used with a block 'can' definition
        # Need to switch over to SQL permissions, not using the blocks
        Rails.logger.error "Error: resource class, #{@resource_class.name}, is using CanCan block definitions, not SQL permissions. Unable to run index permission filter"
        raise e
      end

      @resources = index_resource_query(@resources)

      respond_with_resources
    end

    def show
      authorize! :show, @resource_class
      # Allow @resource to be set from subclass controller
      @resource ||= @resource_class.find(params[:id])
      authorize! :show, @resource
      
      respond_with_resource
    end

    def new
      authorize! :create, @resource_class
      @resource ||= @resource_class.new(resource_params)
      authorize! :create, @resource

      respond_with_resource
    end

    def edit
      authorize! :update, @resource_class
      @resource ||= @resource_class.find(params[:id])
      authorize! :update, @resource

      respond_to do |format|
        format.html # Renders the default
        format.json { render json: @resources }
        format.xml { render xml: @resources }
        format.csv # Renders the default
        format.xlsx # Renders the default
      end
    end

    def create
      authorize! :create, @resource_class
      @resource ||= @resource_class.new

      service = RecursiveRecordAssignmentAndAuthentication.new(
        current_ability,
        action_name,
        @resource,
        resource_params(@resource)
      )

      if service.call
        respond_with_resource
      else
        begin
          Rails.logger.warn "Failed object validations: could not create #{@resource_class}, id: #{@resource.id}: #{@resource.errors.full_messages}"
          respond_with_resource_invalid
        rescue Exception => e
          Rails.logger.error "CanCanCanResourceController - Caught Internal Server Error: " + e.class.to_s + ': ' + e.message
          Rails.logger.error Rails.backtrace_cleaner.clean(e.backtrace).join("\n").to_s
          respond_with_resource_error
        end
      end
    end

    def update
      authorize! :update, @resource_class
      @resource ||= @resource_class.find(params[:id])
      service = RecursiveRecordAssignmentAndAuthentication.new(
        current_ability,
        action_name,
        @resource,
        resource_params(@resource)
      )

      if service.call
        respond_with_resource
      else
        begin
          Rails.logger.warn "Failed object validations: could not update #{@resource_class}, id: #{@resource.id}: #{@resource.errors.full_messages}"
          respond_with_resource_error
        rescue Exception => e
          Rails.logger.error "CanCanCanResourceController - Caught Internal Server Error: " + e.class.to_s + ': ' + e.message
          Rails.logger.error Rails.backtrace_cleaner.clean(e.backtrace).join("\n").to_s
          respond_with_resource_error
        end
      end
    end

    def destroy
      authorize! :destroy, @resource_class
      @resource ||= @resource_class.find(params[:id])
      authorize! :destroy, @resource
      # retuning the resource in a pre-destroyed state as a destroy response
      if @resource.destroy
        respond_after_destroy
      else
        begin
          Rails.logger.warn "Failed object validations: could not destroy #{@resource_class}, id: #{@resource.id}: #{@resource.errors.full_messages}"
          respond_with_resource_invalid
        rescue Exception => e
          Rails.logger.error "CanCanCanResourceController - Caught Internal Server Error: " + e.class.to_s + ': ' + e.message
          Rails.logger.error Rails.backtrace_cleaner.clean(e.backtrace).join("\n").to_s
          respond_with_resource_error
        end
      end
    end

    protected

    def respond_with_resources
      respond_to do |format|
        format.html # Renders the default
        format.json { render json: @resources }
      end
    end

    def respond_with_resource
      respond_to do |format|
        format.html # Renders the default
        format.json { render json: @resource }
      end
    end

    def respond_with_resource_invalid
      respond_to do |format|
        format.html # Renders the default
        format.json { render json: @resource.errors.full_messages, status: 422 }
      end
    end

    def respond_with_resource_error
      respond_to do |format|
        format.html # Renders the default
        format.json { render json: ["An error has occured. Our support teams have been notified and are working on a solution."], status: 422 }
      end
    end

    def respond_after_destroy
      respond_to do |format|
        format.html { redirect_to url_for(controller: controller_name, action: 'index') }
        format.json { render json: @resource, status: :no_content }
      end
    end

    # meant to be overridden by inheriting controllers.
    def index_resource_query resource_query
      return resource_query
    end

    # can pass in custom method to supplant 'param.permit', like if you wanted to whitelist a hash instead of params.
    # ex: CanCanCanResourceController#deactivate_helper, permits on fake params: ActionController::Parameters.new(deactive_params)
    def resource_params resource_object = nil, opts = {}, &block
      local_action_name = opts[:custom_action_name] || action_name
      allowlist_permitted = get_nested_attributes_for_class(@resource_class, local_action_name.to_sym, resource_object)

      # # Rails kludge, issue with allowing parameters with empty arrays
      # # Needs to be nested, recursive
      # # Updating params in-place
      # params.each do |key, value|
      #   if key.to_s =~ /(.*)_ids/ && (value == "remove" || value == ["remove"])
      #     params[key] = []
      #   end
      # end

      if block_given?
        params_with_only_allowed_parameters = yield(allowlist_permitted)
      else
        params_with_only_allowed_parameters = param_permit(allowlist_permitted)
      end

      # sanitize all input.
      sanitized_params_with_only_allowed_parameters = clean_parameter_data(params_with_only_allowed_parameters)

      # recast type (and have to re-permit)
      sanitized_params_with_only_allowed_parameters = ActionController::Parameters.new(sanitized_params_with_only_allowed_parameters).permit(allowlist_permitted)

      return sanitized_params_with_only_allowed_parameters
    end

    # recursive
    # src: https://apidock.com/rails/v5.2.3/ActionView/Helpers/SanitizeHelper/sanitize
    def clean_parameter_data param_value
      # was an array element, and not an object.
      # Check for HTML tags
      if param_value.is_a?(String) && !(param_value =~ REGEX_FOR_HTML_TAG_DETECTION).nil?
        # We need a better way, in the future, to specify the allowed values down to the Class and Column level.
        return ActionController::Base.helpers.sanitize(param_value, {tags: self.class::DEFAULT_PARAMETER_SANITIZER_ALLOWED_TAGS, attributes: self.class::DEFAULT_PARAMETER_SANITIZER_ALLOWED_ATTRIBS})
      elsif param_value.is_a?(String) || param_value.is_a?(Integer) || param_value.is_a?(Float) || param_value.nil? || [true, false].include?(param_value)
        return param_value
      end

      if param_value.is_a?(Hash) || param_value.is_a?(Array) || param_value.is_a?(ActionController::Parameters)
        # good to continue
      else
        error_msg = "Internal Server Error! Unsupported parameter type: #{param_value} (#{param_value.class})"
        Rails.logger.error(error_msg)
        raise error_msg
      end

      if param_value.is_a?(Array)
        new_array = []
        param_value.each do |array_element|
          new_array << clean_parameter_data(array_element)
        end
        return new_array
      else
        new_hash = {}
        keys = param_value.keys
        keys.each do |key|
          new_hash[key.to_sym] = clean_parameter_data(param_value[key])
        end
        return new_hash
      end
    end

    # Not checking instances of classes. What if they are object-state dependent?
    # Need to run them again, after object instantiation, but in a different method.
    def get_nested_attributes_for_class resource_class, action_name, root_level_object, depth = 0
      raise "invalid action class: #{action_name.class}" if !action_name.is_a?(Symbol)
      association_parameters = []
      if depth > MAX_ASSOCIATIVE_NESTED_DEPTH
        return association_parameters
      end

      # Handle resource_class attribs
      # issue here is the 'action_name' on the root 'resource_class' may not be the action that the user has for the 'assoc_class'
      # i.e:
      #   We may want the user to update Account, and create attachments on it, but not 'update' attachments.
      if depth == 0
        association_parameters = current_ability.permitted_attributes(action_name, (root_level_object || resource_class)) 
      else
        association_parameters = current_ability.permitted_attributes(action_name, resource_class)
      end

      if resource_class.const_defined?('RESOURCE_CONTROLLER_ATTRIB_ALLOWLIST') && !resource_class::RESOURCE_CONTROLLER_ATTRIB_ALLOWLIST.nil?
        association_parameters &= resource_class::RESOURCE_CONTROLLER_ATTRIB_ALLOWLIST
      end

      # remove customized, non-params, assoc' attrib data by only allowing class columns
      association_parameters &= resource_class.column_names.collect(&:to_sym)

      resource_class.reflect_on_all_associations(:has_many).each do |assoc_class|
        resource_key = assoc_class.name
        # attrib_permission_key = (resource_key.to_s.singularize + '_ids').to_sym
        attrib_permission_key = IDS_ATTIB_PERMISSION_KEY_GEN.call(resource_key)
        # action_permission_key = ('_can_add_or_remove_association_' + resource_key.to_s).to_sym
        action_permission_key = IDS_ACTION_PERMISSION_KEY_GEN.call(resource_key)
        # i.e. can?(:can_participation_ids, Account)
        # Check to see if we manually gave the user a custom permission
        # # (i.e.: can [:update, :can_account_sector_ids], Account)
        # OR
        # see if it has the attribute on the class's allowed params
        if can?(action_permission_key, resource_class) || can?(action_name, resource_class, attrib_permission_key)
          association_parameters << {
            attrib_permission_key => []
          }
        end
      end

      resource_class.nested_attributes_options.each do |resource_key, options|
        reflection_class = resource_class.reflect_on_association(resource_key).class
        reflection_type  = reflection_class.name
        assoc_class = resource_class.reflect_on_association(resource_key).klass

        if [
          "ActiveRecord::Reflection::BelongsToReflection",
          "ActiveRecord::Reflection::HasOneReflection",
          "ActiveRecord::Reflection::HasManyReflection"
        ].include?(reflection_type)
          parameter_key = NESTED_ATTIB_PERMISSION_KEY_GEN.call(resource_key)
          permission_key = NESTED_ACTION_PERMISSION_KEY_GEN.call(resource_key)

          # Can check if permission to update assoc is defined as an action OR as an attrib on the parent resource_class
          if can?(permission_key, resource_class) || can?(action_name, resource_class, parameter_key)
            # Handle recursion
            assoc_parameters = get_nested_attributes_for_class(assoc_class, action_name, root_level_object, depth + 1)

            if options[:allow_destroy] && can?(:destroy, resource_class)
              assoc_parameters << :_destroy
            end

            association_parameters << {
              parameter_key => assoc_parameters
            }
          end
        end
      end

      return association_parameters
    end

    def param_permit base_parameters
      params.permit(base_parameters)
    end

    def initialize_resource_class
      # First priority is the namespaced model, e.g. User::Group
      @resource_class ||= begin
        namespaced_class = self.class.name.sub(/Controller$/, '').singularize
        namespaced_class.constantize
      rescue NameError
        nil
      end

      # Second priority is the top namespace model, e.g. EngineName::Article for EngineName::Admin::ArticlesController
      @resource_class ||= begin
        namespaced_classes = self.class.name.sub(/Controller$/, '').split('::')
        namespaced_class = [namespaced_classes.first, namespaced_classes.last].join('::').singularize
        namespaced_class.constantize
      rescue NameError
        nil
      end

      # Third priority the camelcased c, i.e. UserGroup
      @resource_class ||= begin
        camelcased_class = self.class.name.sub(/Controller$/, '').gsub('::', '').singularize
        camelcased_class.constantize
      rescue NameError
        nil
      end

      # Otherwise use the Group class, or fail
      @resource_class ||= begin
        class_name = self.controller_name.classify
        class_name.constantize
      rescue NameError => e
        raise unless e.message.include?(class_name)
        nil
      end
      # portal/portal_imports case needed this
      @resource_class ||= begin
        class_name = controller_path.classify
        class_name.camelize.singularize.constantize
      rescue NameError => e
        raise unless e.message.include?(class_name)
        nil
      end
    end

  end
end