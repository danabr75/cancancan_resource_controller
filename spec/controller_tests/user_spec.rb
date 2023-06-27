require 'rails_helper'

RSpec.describe UsersController, type: :controller do
  fixtures :users, :vehicles, :parts, :groups, :groups_users, :brands
  let(:normal_user) {
     User.find_by_email('test2@test.test')
  }
  let(:staff_user) {
     User.find_by_email('test@test.test')
  }

  it "is available as described_class" do
    expect(described_class).to eq(UsersController)
  end


  describe "staff user" do
    before do
      allow_any_instance_of(described_class).to receive(:current_ability).and_return(staff_user.current_ability)
    end

    it "should update all attribs for a staff user" do
      user = staff_user
      allow_any_instance_of(described_class).to receive(:current_ability).and_return(user.current_ability)
      expect(controller.current_ability.permitted_attributes(:update, user).sort).to eq([:first_name, :last_name, :vehicles_attributes, :group_ids].sort)
      expect(described_class.new.current_ability.permitted_attributes(:update, user).sort).to eq([:first_name, :last_name, :vehicles_attributes, :group_ids].sort)

      expect(user.current_ability.can?(:update, User, :vehicles_attributes)).to eq(true)
      expect(user.current_ability.can?(:update, User, 'vehicles_attributes')).to eq(true)

      # confirm initial state
      expect(user.full_name).to eq("Ben Dana")
      expect(user.vehicles.pluck(:make, :model)).to eq([["Dodge", "Caraven"], ["Tesla", "Roadster"], ["Ford", "Firebird"], ["Honda", "Rebel"]])
      expect(user.vehicles.find_by_model("Caraven").parts.pluck(:name)).to eq(["Engine", "Frame"])
      update_vehicle = user.vehicles.where(make: "Dodge", model: "Caraven").first
      update_part    = update_vehicle.parts.find_by_name("Frame")
      expect(user.group_ids).to eq([Group.find_by_name("Notification List A").id])
      expect(Part.find_by_name("Frame").brand_ids).to eq([])

      params = {
        id: user.id,
        first_name: "Benjamin",
        last_name: "Denar",
        email: "dontupdate@here.there",
        group_ids: user.group_ids + [Group.find_by_name("Notification List B").id],
        # was initially a create vehicle, but SQLite3 had issues with creating the vehicle ID.
        vehicles_attributes: [{
          id: update_vehicle.id,
          make: 'makey',
          model: 'modely',
          parts_attributes: [{
            id: update_part.id,
            name: "Frame (warped)",
            brand_ids: [Brand.find_by_name('Cromwell').id],
          }],
        }],
      }

      response = post(:update, params: params, as: :json)
      expect(response.status).to eq(200)

      user = User.find_by_email('test@test.test')
      expect(user.full_name).to eq("Benjamin Denar")
      expect(user.vehicles.pluck(:make, :model)).to eq([["makey", "modely"], ["Tesla", "Roadster"], ["Ford", "Firebird"], ["Honda", "Rebel"]])
      expect(user.vehicles.find_by_model("modely").parts.pluck(:name)).to eq(["Engine", "Frame (warped)"])
      expect(user.group_ids).to eq([Group.find_by_name("Notification List A").id, Group.find_by_name("Notification List B").id])
      expect(Part.find_by_name("Frame (warped)").brand_ids).to eq([Brand.find_by_name('Cromwell').id])
    end
  end

  describe "normal user" do
    before do
      allow_any_instance_of(described_class).to receive(:current_ability).and_return(normal_user.current_ability)
    end

    it "should update all attribs for a normal user" do
      user = normal_user
      allow_any_instance_of(described_class).to receive(:current_ability).and_return(user.current_ability)
      ability = controller.current_ability
      expect(ability.permitted_attributes(:update, user).sort).to eq([:first_name, :last_name].sort)

      # confirm initial state
      expect(user.full_name).to eq("Victor Frankenstein")
      expect(user.vehicles.sort).to eq([].sort)

      update_vehicle = Vehicle.where(make: "Dodge", model: "Caraven").first
      update_part    = update_vehicle.parts.find_by_name("Frame")

      params = {
        id: user.id,
        first_name: "Alen",
        last_name: "Tom",
        email: "dontupdate@here.there",
        group_ids: user.group_ids + [Group.find_by_name("Notification List B").id],
        vehicles_attributes: [{
          id: update_vehicle.id,
          make: 'makey',
          model: 'modely',
          parts_attributes: [{
            id: update_part.id,
            name: "Frame (warped)",
            brand_ids: [Brand.find_by_name('Cromwell').id],
          }],
        }],
      }

      response = post(:update, params: params, as: :json)
      expect(response.status).to eq(200)

      user = User.find_by_email('test2@test.test')
      expect(user.full_name).to eq("Alen Tom")
      expect(user.vehicles.sort).to eq([].sort)
      expect(user.group_ids).to eq([])
      expect(Part.find_by_name("Frame").brand_ids).to eq([])
    end
  end
end