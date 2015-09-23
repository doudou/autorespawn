# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'autorespawn/version'

Gem::Specification.new do |spec|
  spec.name          = "autorespawn"
  spec.version       = Autorespawn::VERSION
  spec.authors       = ["Sylvain Joyeux"]
  spec.email         = ["sylvain.joyeux@m4x.org"]

  spec.required_ruby_version = ">= 2.1.0"

  spec.summary       = "functionality to respawn a Ruby program when its source changes"
  spec.description   =<<-EOD
This gem implements the functionality to take a signature of the current Ruby
program (i.e. the current process) and respawn it whenever the source code or
libraries change
EOD
  spec.homepage      = "https://github.com/doudou/autorespawn"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "hooks", ">= 0.4.1"
  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", ">= 5.0", "~> 5.0"
  spec.add_development_dependency "fakefs", ">= 0.6", "~> 0.6.0"
  spec.add_development_dependency 'flexmock', ">= 2.0", '~> 2.0'
  spec.add_development_dependency "coveralls"
end
