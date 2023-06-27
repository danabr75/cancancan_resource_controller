puts 'attempting to load'
# Dir[File.join(__dir__, '..', 'app', 'controllers', '**', '*.rb')].each {|file| puts "file: #{file}"; require file }
require_relative 'cancancan/abstract_resource_controller'
# Dir[File.join(Rails.root, 'app', 'helpers', '**', '*.rb')].each {|file| require file }

# include the extension 
# ActiveRecord::Base.send(:include, Serializer::Concern)