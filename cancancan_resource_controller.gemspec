# gem build rails_json_serializer.gemspec

Gem::Specification.new do |s|
  s.name = %q{cancancan_resource_controller}
  s.version = "0.0.1"
  s.date = %q{2023-07-27}
  s.authors = ["benjamin.dana.software.dev@gmail.com"]
  s.summary = %q{A Rails Controller Module that uses CanCan's permitted attribs instead of typical parameter allowlisting.}
  s.licenses = ['LGPL-3.0-only']
  s.files = [
    "lib/cancancan_resource_controller.rb",
    "lib/cancancan/abstract_resource_controller.rb",
  ]
  s.require_paths = ["lib"]
  s.homepage = 'https://github.com/danabr75/rails_json_serializer'
  s.add_runtime_dependency 'rails', '>= 5.0'
  s.add_runtime_dependency 'zlib', '>= 1.0'
  s.add_development_dependency 'rails', ['~> 5.0']
  s.add_development_dependency "rspec", ["~> 3.9"]
  s.add_development_dependency "listen", ["~> 3.2"]
  s.add_development_dependency "rspec-rails", ["~> 4.0"]
  s.add_development_dependency "database_cleaner", ["~> 1.8"]
  s.add_development_dependency "sqlite3", ["~> 1.4"]
  s.required_ruby_version = '>= 2.4'
end