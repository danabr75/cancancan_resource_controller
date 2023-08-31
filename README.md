# Use CanCan's :permitted_attributes method to automatically determine controller permitted parameters.
CanCan provides a way to set permitted attributes, so why build something else?

# Install (add to Gemfile)
```
gem 'cancancan_resource_controller', '~> 1'
```

# Usage:
(Optional) create init file: config/initializers/cancancan_resource_controller.rb and populate it with the following:

```
require "cancancan_resource_controller"
# default values shown
CanCanCan::AbstractResourceController.configure do |config|
  # Allows for stopping unauthorized actions without raising errors
  # - Will let root object (and valid, other nested objects) save, even if an invalid nested object exists, if true
  config.silence_raised_errors = false
  # Auto-determine what action to auth on nested associations (:create, :update, :destroy)
  # - :create if is a new record
  # - :update if pre-existing record
  # - :destroy if :_destroy parameter is present
  # - will use the action of the root object if set to false
  config.use_smart_nested_authorizations = true
end
```

## Mainly built out the :create, :update, and :destroy methods. We also have the :index and :show methods, but I would recommend overriding those.
```
class UsersController < ActionController::Base
  include CanCanCan::AbstractResourceController

  # index, update, create, destroy methods are now provided and backed by CanCan's Ability settings.

  # All actions use the following to pull the object from the database:
  # `@resource ||= @resource_class.find(params[:id])`
  # if you need to locate the object yourself, or apply additional logic, you can use a `before_action` hook.

  # almost all methods will render a @resource object
  # - :index renders a @resources object
  # i.e.:
  # respond_to do |format|
  #   format.html # Renders the default
  #   format.json { render json: @resource }
  # end
end
```

# Handing associations in your ability.rb
```
class User < ApplicationRecord
  has_many :vehicles, inverse_of: :user
  accepts_nested_attributes_for :vehicles, allow_destroy: true
end
class Vehicle < ApplicationRecord
  has_many :vehicles_parts
  has_many :parts, through: :vehicles_parts
  belongs_to :user
end
class Parts < ApplicationRecord
  has_many :vehicles_parts
  has_many :vehicles, through: :vehicles_parts
end

class Ability
  include CanCan::Ability

  def initialize(user = nil)
    # Nested Attribs

    # METHOD 1 (attrib)
    # - `association_name + '_attributes'`
    # - :vehicles_attributes will be used to permit it's usage in your controller
    can :update, User, [:first_name, :last_name, :vehicles_attributes]

    # METHOD 2 (action)
    # - `'_can_add_or_remove_association_' + association_name`
    # - same result as Method 1, alternate approach.
    # - useful if you aren't interested in spelling out all your permitted_attributes.
    can :_can_update_association_vehicles, User

    # Add/Remove IDs from has_many assocation

    # METHOD 1 (attrib):
    # - `association_name.singularize + '_ids'`
    can :update, Vehicle, [:make, :model, :part_ids]

    # METHOD 2 (action)
    # - `'_can_add_or_remove_association_' + association_name`
    can :_can_add_or_remove_association_parts, Vehicle
  end
end
```


# Shortcoming A:
Currently we do not instantiate the nested assocations to run permission checks at the object level. We only run class checks on associations. We run instance level checks only on the root object.

# Shortcoming B:
When updating a parent object, and at the same time creating a nested assocation, the action that would be checked for both parent and nested object would the be the :update action. Ideally, we would use the :create action for that assocation. This is also due to us not currently trying to instantiate nested associations

# Warning:
Leaving off the permitted_attributes parameter entirely will allow ALL attributes AND associations to be passed through.  
`can :update, User#, [will allow all attribs and associations]`
