# frozen_string_literal: true

require_relative "lib/floe/version"

Gem::Specification.new do |spec|
  spec.name = "floe"
  spec.version = Floe::VERSION
  spec.authors = ["ManageIQ Developers"]

  spec.summary = "Floe is a runner for Amazon States Language workflows."
  spec.description = spec.summary
  spec.homepage = "https://github.com/ManageIQ/floe"
  spec.licenses = ["Apache-2.0"]
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata['rubygems_mfa_required'] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">5.2"
  spec.add_dependency "aws-sdk-s3", "~>1.0"
  spec.add_dependency "awesome_spawn", "~>1.6"
  spec.add_dependency "faraday"
  spec.add_dependency "faraday-follow_redirects"
  spec.add_dependency "io-wait", ">= 0.3.6", "< 0.5.0"
  spec.add_dependency "json", "~>2.10"
  spec.add_dependency "jsonpath", "~>1.1"
  spec.add_dependency "kubeclient", "~>4.7"
  spec.add_dependency "optimist", "~>3.0"
  spec.add_dependency "parslet", "~>2.0"

  spec.add_development_dependency "manageiq-style"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "simplecov", ">= 0.21.2"
  spec.add_development_dependency "timecop"
end
