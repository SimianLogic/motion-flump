# -*- encoding: utf-8 -*-
VERSION = "0.1"

Gem::Specification.new do |spec|
  spec.name          = "motion-flump"
  spec.version       = VERSION
  spec.authors       = ["Will Hankinson"]
  spec.email         = ["learnyourabcs@gmail.com"]
  spec.description   = %q{A RubyMotoin runtime for Flump, built using native views.}
  spec.summary       = %q{motion-flump is a RubyMotion runtime for Flump, built using native views. Flump is a toolchain for exporting vector animations out from Flash into gpu-friendly formats.}
  spec.homepage      = ""
  spec.license       = "MIT"

  files = []
  files << 'README.md'
  files.concat(Dir.glob('lib/**/*.rb'))
  spec.files         = files
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
end
