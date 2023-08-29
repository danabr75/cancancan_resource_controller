class RecursiveRecordAssignmentAndAuthentication
  attr_reader :ability, :action_name, :parent_object, :params

  def initialize(current_ability, action_name, parent_object, params)
    @ability = current_ability
    @parent_object = parent_object
    @params = params
    @action_name = action_name.to_sym
  end

  def call
    # Pre-assignment auth check
    first_authorize = @ability.can?(@action_name, @parent_object)
    unless first_authorize || CanCanCan::AbstractResourceController.configuration.silence_raised_errors
      raise CanCan::AccessDenied.new("Not authorized!", @action_name, @parent_object)
    end

    return false unless first_authorize

    second_authorize = false
    ActiveRecord::Base.transaction do
      @parent_object.assign_attributes(
        @params.except(
          *@parent_object.class.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
        )
      )
      instantiate_and_assign_nested_associations(
        @parent_object,
        @params.slice(
          *@parent_object.class.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
        )
      )
      # Post-assignment auth check
      second_authorize = @ability.can?(@action_name, @parent_object)
      unless second_authorize
        # NOTE: Does not halt the controller process, just rolls back the DB
        raise ActiveRecord::Rollback
      end
    end

    unless second_authorize || CanCanCan::AbstractResourceController.configuration.silence_raised_errors
      raise CanCan::AccessDenied.new("Not authorized!", @action_name, @parent_object)
    end

    return false unless second_authorize

    return @parent_object.save
  end

  private

  def instantiate_and_assign_nested_associations(parent, param_attribs)
    return if param_attribs.keys.none?

    parent.nested_attributes_options.each_key do |nested_attrib_key|
      param_key = "#{nested_attrib_key}_attributes".to_sym

      next unless param_attribs.key?(param_key)

      reflection = parent.class.reflect_on_association(nested_attrib_key)
      assoc_type = association_type(reflection)
      assoc_klass = reflection.klass

      if assoc_type == :collection
        param_attribs[param_key].each do |attribs|
          child = save_child(
            parent,
            reflection,
            nested_attrib_key,
            attribs.except(
              *assoc_klass.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
            )
          )
          next unless child

          # recursive call
          instantiate_and_assign_nested_associations(
            child,
            attribs.slice(
              *assoc_klass.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
            )
          )
          parent.send(nested_attrib_key).send(:<<, child)
        end
      elsif assoc_type == :singular
        attribs = param_attribs[param_key]
        child = save_child(
          parent,
          reflection,
          nested_attrib_key,
          attribs.except(
            *assoc_klass.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
          )
        )
        next unless child

        # recursive call
        instantiate_and_assign_nested_associations(
          child,
          attribs.slice(
            *assoc_klass.nested_attributes_options.keys.collect { |v| "#{v}_attributes".to_sym }
          )
        )
        parent.send(nested_attrib_key).send(:<<, child)
      else
        # unknown, do nothing
      end
    end

  end

  # NOT RECURSIVE!
  def save_child parent, reflection, nested_attrib_key, attribs
    assoc_klass = reflection.klass
    assoc_primary_key = reflection.options[:primary_key]&.to_sym
    assoc_primary_key ||= :id if assoc_klass.column_names.include?('id')
    assignment_exceptions = [
      :id,
      :_destroy,
      assoc_primary_key
    ] + assoc_klass.nested_attributes_options.keys.collect{ |v| "#{v}_attributes".to_sym }

    # if attribs[assoc_primary_key].present?
    #   puts "CASE 1: #{assoc_primary_key} and #{attribs[assoc_primary_key]}"
    #   child = parent.send(nested_attrib_key).where(assoc_primary_key => attribs[assoc_primary_key]).first
    # else
    #   puts "CASE 2"
    #   child = parent.send(nested_attrib_key).build
    # end

    # Had issues with nested records on other root objects not being able to be updated to be nested under this root object
    if attribs[assoc_primary_key].present?
      child = assoc_klass.where(assoc_primary_key => attribs[assoc_primary_key]).first
    end
    child ||= parent.send(nested_attrib_key).find_or_initialize_by(assoc_primary_key => attribs[assoc_primary_key])

    child_action = @action_name if !CanCanCan::AbstractResourceController.configuration.use_smart_nested_authorizations
    child_action ||= :destroy if reflection.options[:allow_destroy] && ['1', 1, true].include?(attribs[:_destroy])
    child_action ||= :create if child.new_record?
    child_action ||= :update

    # Pre-assignment auth check
    first_authorize = @ability.can?(child_action, child)
    unless first_authorize || CanCanCan::AbstractResourceController.configuration.silence_raised_errors
      raise CanCan::AccessDenied.new("Not authorized!", child_action, child)
    end

    unless first_authorize
      parent.send(nested_attrib_key).delete(child)
      return nil
    end

    second_authorize = false
    ActiveRecord::Base.transaction do
      child.assign_attributes(attribs.except(*assignment_exceptions))
      # Post-assignment auth check
      second_authorize = @ability.can?(child_action, child)
      unless second_authorize
        # NOTE: Does not halt the controller process, just rolls back the DB
        raise ActiveRecord::Rollback
      end
    end

    unless second_authorize || CanCanCan::AbstractResourceController.configuration.silence_raised_errors
      raise CanCan::AccessDenied.new("Not authorized!", child_action, child)
    end

    unless second_authorize
      parent.send(nested_attrib_key).delete(child)
      return nil
    end

    return child
  end

  def association_type(association_reflection)
    case association_reflection.macro
    when :belongs_to, :has_one
      :singular
    when :has_many, :has_and_belongs_to_many
      :collection
    else
      :unknown
    end
  end
end
