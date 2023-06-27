class Ability
  include CanCan::Ability

  def initialize(user = nil)
    if user&.email.present?
      can :update, User, [:first_name, :last_name], { email: user.email }
    end

    if user&.role == 'staff'
      can :update, User, [:first_name, :last_name, :vehicles_attributes, :group_ids]
      can :update, Vehicle
      can :can_update_association_parts, Vehicle
      can :update, Part, [:id, :name]
      can :_can_add_or_remove_association_brands, Part
    end
  end
end
