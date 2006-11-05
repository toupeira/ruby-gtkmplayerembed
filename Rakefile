=begin

  Gtk::MPlayerEmbed - a widget for embedding MPlayer into GTK+ applications.
  Copyright 2006 Markus Koller

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  $Id$

=end

require 'rake/testtask'
begin
  require 'rubygems'
  require 'rake/gempackagetask'
rescue LoadError
  nil
end

desc 'Run unit tests'
task :test do
  Rake::TestTask.new() do |test|
    test.libs << 'lib'
    test.test_files = FileList['test/test*.rb']
    test.warning = true
    test.verbose = true
  end
end

if defined? Gem
  spec = Gem::Specification.new do |spec|
    spec.name = 'gtkmplayerembed'
    spec.version = '0.1.0'
    spec.author = 'Markus Koller'
    spec.email = 'toupeira@gmx.ch'
    spec.homepage = 'http://snafu.selfip.org/software/gtkmplayerembed/'
    spec.platform = Gem::Platform::RUBY
    spec.summary = 'A widget for embedding MPlayer into GTK+ applications'
    spec.files = FileList['{{lib,test,sample}/**/*,[A-Z]*}']
  end
  Rake::GemPackageTask.new(spec).define
end
