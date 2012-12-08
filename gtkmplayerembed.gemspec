# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require File.expand_path('../lib/gtkmplayerembed/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "gtkmplayerembed"
  gem.version       = Gtk::MPlayerEmbed::VERSION
  gem.authors       = ["ToDo: Write your name"]
  gem.email         = ["ToDo: Write your email address"]
  gem.description   = %q{A widget for embedding MPlayer into Ruby/GTK applications}
  gem.summary       = %q{This is a widget for embedding MPlayer into Ruby/GTK applications using the XEMBED protocol}
  gem.homepage      = "" #TODO

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
