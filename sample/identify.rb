#!/usr/bin/env ruby

require 'yaml'
require '../lib/gtkmplayerembed'

ARGV.each do |file|
  puts "identifying #{file}:"
  y Gtk::MPlayerEmbed.identify(file)
end
