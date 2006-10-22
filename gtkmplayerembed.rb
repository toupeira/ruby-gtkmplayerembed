=begin

  Gtk::MPlayerEmbed - a widget for embedding MPlayer into GTK+ applications.
  Copyright 2006 Markus Koller

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  $Id$

=end

require 'gtk2'

module Gtk
  class MPlayerEmbed < EventBox
    type_register
    signal_new 'stopped',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void']
    signal_new 'length_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Integer
    signal_new 'toggle_fullscreen',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void']

    INPUT_PATHS = [ ENV['HOME'] + '/.mplayer/input.conf',
                    '/etc/mplayer/input.conf', ]
    KEYNAMES = {
      'space'     => 'space',
      'bs'        => 'BackSpace',
      'enter'     => 'Return',
      'esc'       => 'Escape',
      'pgup'      => 'Prior',
      'pgdwn'     => 'Next',
      'ins'       => 'Insert',
      'kp_enter'  => 'KP_Enter',
      'kp_ins'    => 'KP_Insert',
      'kp_del'    => 'KP_Delete',
      'kp_dec'    => 'KP_Decimal',
      'del'       => 'Delete',
    }

    attr_accessor :mplayer_path, :mplayer_options, :mplayer_config
    attr_reader :info

    def initialize(path='mplayer', options=nil, config=nil)
      @mplayer_path = path
      @mplayer_options = options
      @mplayer_config = config
      @bindings = {}

      @info = {}
      @answers = {}

      load_bindings

      super()
      modify_bg(Gtk::STATE_NORMAL, style.black)
      set_can_focus(true)
      signal_connect('enter-notify-event') { grab_focus }
      signal_connect('key-press-event') do |w, event|
        puts "#{Gdk::Keyval.to_name(event.keyval)} => #{event.keyval}"
        case command = @bindings[event.keyval]
        when 'vo_fullscreen'
          signal_emit 'toggle_fullscreen'
        when /^vo_ontop/
          toplevel.keep_above = true if toplevel
        else
          send_command command
        end
      end

      @aspect = Gtk::AspectFrame.new(nil, 0.5, 0.5, 16/9.0, false)
      @aspect.shadow_type = Gtk::SHADOW_NONE
      self << @aspect

      @socket = Gtk::Socket.new
      @socket.set_size_request(1, 1)
      @socket.modify_bg(Gtk::STATE_NORMAL, style.black)
      @aspect << @socket
    end

    def play(files)
      open_thread unless thread_alive?
      send_command :loadfile => files
      puts 'playing!!!'
    end

    def stop
      send_command :quit
    end

    def kill_thread
      puts 'killing'
      Process.kill 'INT', @pipe.pid if thread_alive?
      @thread.join if @thread
      @thread = nil
      @pipe = nil
    end

    [ :pause, :mute, :switch_audio ].each do |cmd|
      define_method(cmd) { send_command cmd }
    end

    def ratio
      @aspect.ratio
    end

    def ratio=(ratio)
      @info[:ratio] = ratio
      @aspect.ratio = ratio
    end

  private

    def signal_do_length_changed(length) end
    def signal_do_stopped() end
    def signal_do_toggle_fullscreen() end

    def load_bindings
      if file = INPUT_PATHS.find { |f| File.readable? f }
        File.readlines(file).each do |line|
          if line =~ /^([^# ]+) (.+)$/
            if $1.size == 1
              keyval = Gdk::Keyval.from_unicode $1
            elsif name = KEYNAMES[$1.downcase]
              keyval = Gdk::Keyval.from_name name
            else
              keyval = Gdk::Keyval.from_name $1.capitalize
            end
            @bindings[keyval] = $2 if keyval > 0
          end
        end
      end
    end

    def thread_alive?
      @pipe.flush and true rescue false
    end

    def send_command(cmd)
      if cmd.is_a? Hash
        if cmd.values.first.is_a? Array
          args = cmd.values.first.map { |a| a.inspect}.join ' '
        else
          args = cmd.values.first.inspect
        end
        command = "#{cmd.keys.first} #{args}"
        open_thread if cmd[:open] and not thread_alive?
      else
        command = cmd
      end
      if thread_alive?
        puts "sending #{command.inspect}"
        @pipe.write "#{command}\n"
      end
    end

    def open_thread
      return if thread_alive?

      x = @socket.allocation.width
      y = @socket.allocation.height
      cmd = "#{@mplayer_path} -slave -idle -quiet -identify " +
            "#{'-include '+@mplayer_config if @mplayer_config}" +
            "-wid #{@socket.id} -geometry #{x}x#{y} #{@mplayer_options}"
      puts "opening slave with #{cmd}"

      @answers = {}
      @pipe = IO.popen(cmd, 'a+')
      @thread = Thread.new { slave_reader }
      #Gtk.timeout_add(1000) do
      #  send_command 'pausing_keep get_time_pos'
      #  puts @answers['TIME_POSITION']
      #  thread_alive?
      #end
    end

    def slave_reader
      until @pipe.eof? or @pipe.closed?
        if @aspect.nil? or @aspect.destroyed?
          kill_slave
          break
        end
        line = @pipe.readline.chomp
        if match = /^([a-z_]+)=(.+)$/i.match(line)
          puts line
          key, value = match.captures
          case key
          when 'ID_FILENAME'
            @info = { :file => File.basename(value), :width => 0 }
          when 'ID_LENGTH'
            @info[:length] = value.to_i
            signal_emit 'length_changed', @info[:length]
          when 'ID_VIDEO_WIDTH'
            @info[:width] = value.to_i if value
          when 'ID_VIDEO_HEIGHT'
            if @info[:width] > 0 and (@info[:height] = value.to_f) > 0
              Gtk.idle { self.ratio = @info[:width] / @info[:height] }
            end
          when 'ID_VIDEO_ASPECT'
            unless (ratio = value.to_f).zero?
              puts "changing aspect ratio to #{ratio}"
              Gtk.idle { self.ratio = ratio }
            end
          when /^ID_([a-z_]+)$/i
            if value
              @info[$1.downcase.to_sym] = value.to_i > 0 ? value.to_i : value
            end
          when /^ANS_([a-z_]+)$/i
            @answers[$1] = value
          end
        end
      end
    ensure
      @pipe.close if @pipe
      @pipe = nil
      @thread = nil
      puts 'thread stopped.'
      signal_emit 'stopped'
    end
  end

  def self.idle
    Gtk.idle_add do
      yield
      false
    end
  end
end
