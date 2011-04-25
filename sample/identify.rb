#!/usr/bin/env ruby

require 'yaml'
require 'pathname'
require "#{Pathname.new(__FILE__).realpath.parent}/../lib/gtkmplayerembed"

ARGV.each do |file|
  puts "identifying #{file}:"
  y Gtk::MPlayerEmbed.identify(file)
  puts
end
