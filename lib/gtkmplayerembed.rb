=begin

  Gtk::MPlayerEmbed - a widget for embedding MPlayer into GTK+ applications.
  Copyright 2006 Markus Koller

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  $Id$

=end

require 'gtk2'
require 'tempfile'

module Gtk
  def self.idle
    Gtk.idle_add { yield; false }
  end

  class MPlayerEmbed < EventBox
    type_register
    signal_new 'stopped',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void']
    signal_new 'file_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], String
    signal_new 'properties_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Hash
    signal_new 'playlist_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Array
    signal_new 'length_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Integer
    signal_new 'fullscreen_toggled',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], TrueClass

    INPUT_PATHS = [ "#{ENV['HOME']}/.mplayer/input.conf",
                    "/etc/mplayer/input.conf" ]
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

    attr_accessor :mplayer_path, :mplayer_options, :bg_stripes
    attr_reader :config, :file, :playlist, :fullscreen_size,
                :bg_color, :bg_logo, :bg_stripes_color

    def initialize(path='mplayer', options=nil)
      @mplayer_path = path
      @mplayer_options = options

      @fs_window = nil
      @fullscreen_size = [ Gdk::Screen.default.width,
                           Gdk::Screen.default.height ]

      @bg_color = Gdk::Color.parse('black')
      @bg_stripes_color = Gdk::Color.parse('#333')

      @file = {}
      @answers = {}
      @bindings = {}
      load_bindings

      super()
      modify_bg(Gtk::STATE_NORMAL, @bg_color)
      set_can_focus(true)
      set_size_request(10, 10)

      signal_connect('show') { @aspect.hide unless thread_alive? }
      signal_connect('expose-event') { draw_background unless thread_alive? }
      signal_connect('enter-notify-event') { grab_focus }

      signal_connect('button-press-event') do |w, event|
        toggle_fullscreen if event.button == 3
      end
      signal_connect('key-press-event') do |w, event|
        case command = @bindings[event.keyval]
        when Proc
          command.call
        when /vo_fullscreen/
          toggle_fullscreen
        when /vo_ontop/
          toplevel.keep_above = true if toplevel
        else
          send_command(command) if command
        end
      end

      @aspect = Gtk::AspectFrame.new(nil, 0.5, 0.5, 16/9.0, false)
      @aspect.shadow_type = Gtk::SHADOW_NONE
      self << @aspect

      @socket = Gtk::Socket.new
      @socket.modify_bg(Gtk::STATE_NORMAL, @bg_color)
      @aspect << @socket

      at_exit { kill_thread }
    end

    def fullscreen?
      @fs_window.is_a? Gtk::Window and toplevel == @fs_window
    end

    def fullscreen=(status)
      toggle_fullscreen unless fullscreen? == status
    end

    def toggle_fullscreen
      if fullscreen?
        reparent(@parent)
        @fs_window.destroy
        @fs_window = nil
      else
        @parent = parent
        @fs_window = Gtk::Window.new
        @fs_window.modify_bg(Gtk::STATE_NORMAL, style.black)
        @fs_window.fullscreen
        @fs_window.signal_connect('key-press-event') do |win, event|
          self.event(event)
        end

        align = Gtk::Alignment.new(0, 0, 1, 1)
        @fs_window << align

        screenx, screeny = Gdk.screen_width, Gdk.screen_height
        width = [ 320, [ screenx, @fullscreen_size[0] ].min ].max
        height = [ 240, [ screeny, @fullscreen_size[1] ].min ].max
        align.set_right_padding(screenx - width)
        align.set_bottom_padding(screeny - height)

        align.realize
        reparent(align)
        @fs_window.show_all
        @aspect.hide unless thread_alive?
      end
      signal_emit 'fullscreen_toggled', fullscreen?
    end

    def play(files)
      signal_emit 'playlist_changed', @playlist = Array(files)
      @tmp = Tempfile.new('gtkmplayerembed')
      @playlist.each { |f| @tmp.write("#{f}\n") }
      @tmp.close
      if thread_alive?
        send_command :loadlist => @tmp.path
      else
        open_thread("-playlist #{@tmp.path}")
      end
    end

    def stop
      send_command :quit
    end

    def next(step=1)
      send_command :pt_step => step
    end

    def previous(step=1)
      send_command :pt_step => -step
    end

    def seek(step)
      send_command :seek => step, :pausing => 'keep'
    end

    [ :pause, :mute, :switch_audio ].each do |cmd|
      define_method(cmd) { send_command cmd }
    end

    def add_binding(key, command=nil, &block)
      if key.size == 1
        keyval = Gdk::Keyval.from_unicode(key)
      elsif name = KEYNAMES[key.downcase]
        keyval = Gdk::Keyval.from_name(name)
      elsif (keyval = Gdk::Keyval.from_name(key)).zero?
        keyval = Gdk::Keyval.from_name(key.capitalize)
      end

      if keyval > 0
        command = block ? block : command
        raise "no command or block given." unless command
      else
        debug "couldn't find keycode for #{key.inspect}"
      end

      @bindings[keyval] = command
    end

    def show_text(text, time=2000)
      send_command :osd_show_text => [ text, time ], :pausing => 'keep'
    end

    def thread_alive?
      @thread and @pipe.flush and true rescue false
    end

    def kill_thread
      Process.kill 'INT', @pipe.pid if thread_alive?
      @thread.join if @thread
      @thread = nil
      @pipe = nil
    end

    def ratio
      @aspect.ratio
    end

    def ratio=(ratio)
      @file[:ratio] = ratio
      @aspect.ratio = ratio
    end

    def fullscreen_size=(*size)
      size.flatten!
      if size.size == 2 and size.all? { |i| i.is_a? Integer }
        @fullscreen_size = size
      else
        raise ArgumentError, "invalid size"
      end
    end

    def bg_color=(color)
      color = Gdk::Color.parse(color) unless color.is_a? Gdk::Color
      modify_bg(Gtk::STATE_NORMAL, color)
      @socket.modify_bg(Gtk::STATE_NORMAL, color)
      @bg_color = color
    end

    def bg_logo=(logo)
      logo = Gdk::Pixbuf.new(logo) unless logo.is_a? Gdk::Pixbuf
      @bg_logo = logo
    end

    def bg_stripes_color=(color)
      color = Gdk::Color.parse(color) unless color.is_a? Gdk::Color
      @bg_stripes_color = color
    end

    def send_command(*args)
      command = nil
      args.each do |value|
        case value
        when String, Symbol
          command = value
        when Hash
          value.each do |key, value|
            case key
            when :open
              open_thread if value
            when :pausing
              command = if value.is_a? String
                "pausing_#{value} #{command}"
              else
                "pausing #{command}"
              end
            else
              args = Array(value).map { |a| a.inspect }.join ' '
              command = "#{key} #{args}"
            end
          end
        end
      end
      raise ArgumentError, "invalid arguments" unless command
      if thread_alive?
        debug "sending #{command.inspect}"
        @pipe.write "#{command}\n"
      end
    end

    def read_command(command, key)
      @answers.delete(key)
      send_command command, :pausing => 'keep'
      i = 0
      sleep 0.005 until @answers[key] or (i += 1) > 10
      @answers[key]
    end

  private

    def debug(message)
      puts "[Gtk::MPlayerEmbed::#{$$}] #{message}" if $DEBUG
    end

    def signal_do_stopped
      debug "#{@thread.inspect} stopped"
      @pipe = nil
      @thread = nil
      @file = {}

      @aspect.hide
      toggle_fullscreen if fullscreen?
    end

    def signal_do_file_changed(file) end
    def signal_do_properties_changed(properties) end
    def signal_do_playlist_changed(playlist) end
    def signal_do_length_changed(length) end
    def signal_do_fullscreen_toggled(fullscreen) end

    def format_time(time)
      time = time.to_i
      "%02d:%02d:%02d" % [time / 3600, (time % 3600) / 60, time % 60]
    end

    def load_bindings
      if file = INPUT_PATHS.find { |f| File.readable? f }
        debug "reading bindings from #{file}"
        File.readlines(file).each do |line|
          if line =~ /^([^# ]+) (.+)$/
            add_binding($1, $2)
          end
        end
      end

      add_binding('i') do
        next unless @file[:path]
        pos = format_time(read_command(:get_time_pos, 'TIME_POSITION'))
        length = format_time(@file[:length])
        percent = read_command(:get_percent_pos, 'PERCENT_POSITION')
        show_text "#{File.basename(@file[:path])}   #{pos} / #{length}   (#{percent}%)"
      end

      add_binding('c') do
        show_text Time.now.strftime('%T')
      end
    end

    def open_thread(options=nil)
      return if thread_alive?
      @aspect.show_all
      x = @socket.allocation.width
      y = @socket.allocation.height
      cmd = "#{@mplayer_path} -slave -quiet -identify " +
            "-wid #{@socket.id} -geometry #{x}x#{y} " +
            "#{options} #{@mplayer_options}"
      debug "running thread with #{cmd.inspect}"
      @thread = Thread.new { slave_reader(cmd) }
    end

    def slave_reader(command)
      @answers = {}
      @pipe = IO.popen(command, 'a+')
      until @pipe.eof? or @pipe.closed?
        if @aspect.nil? or @aspect.destroyed?
          kill_slave
          break
        end

        line = @pipe.readline.chomp
        if line == 'Starting playback...'
          signal_emit('properties_changed', @file)
        elsif match = /^([a-z_ ]+)[=:](.+)$/i.match(line)
          key, value = match.captures
          key.strip!
          value.strip!

          case key
          when 'ID_FILENAME'
            @file = { :path => value, :width => 0 }
            signal_emit 'file_changed', value
          when 'ID_LENGTH'
            @file[:length] = value.to_i
            signal_emit 'length_changed', @file[:length]
          when 'ID_VIDEO_WIDTH'
            if (width = value.to_i) > 0
              @file[:width] = width
            end
          when 'ID_VIDEO_HEIGHT'
            if @file[:width] and (@file[:height] = value.to_i) > 0
              Gtk.idle { self.ratio = @file[:width].to_f / @file[:height] }
            end
          when 'ID_VIDEO_ASPECT'
            unless (ratio = value.to_f).zero?
              debug "changing aspect ratio to #{ratio}"
              Gtk.idle { self.ratio = ratio }
            end
          when /^ID_(\w+)$/
            if value
              @file[$1.downcase.intern] = case value
                when /^\d+$/: value.to_i
                when /^\d+\.\d+$/: value.to_f
                else value
              end
            end
          when /^ANS_(\w+)$/
            @answers[$1] = value
          when /^Language$/
            @file[:language] = value[/^([^\[]+)/, 1] || value
          when /^Selected (audio|video) codec$/
            @file["#{$1}_codec".intern] = value[/\((.*)\)/, 1] || value
          else
            debug "didn't recognize #{key.inspect} => #{value.inspect}"
            next
          end
          debug "recognized #{key.inspect} => #{value.inspect}"
        end
      end
    rescue Exception => exc
      Gtk.idle { raise exc }
    ensure
      signal_emit 'stopped'
    end

    def draw_background
      gc = Gdk::GC.new(window)
      gc.rgb_fg_color = @bg_color
      x, y, width, height = allocation.to_a
      window.draw_rectangle(gc, true, 0, 0, width, height)

      if @bg_stripes and @bg_stripes_color.is_a? Gdk::Color
        gc.rgb_fg_color = @bg_stripes_color
        0.step(height, 4) do |y|
          window.draw_rectangle(gc, true, 0, y, width, 2)
        end
      end

      if @bg_logo.is_a? Gdk::Pixbuf
        lwidth, lheight = @bg_logo.width, @bg_logo.height
        if lwidth > width or lheight > height
          xratio = width / lwidth.to_f
          yratio = height / lheight.to_f
          ratio = xratio > yratio ? yratio : xratio
          pixbuf = @bg_logo.scale(lwidth * ratio, lheight * ratio)
        else
          pixbuf = @bg_logo
        end

        x = width / 2 - pixbuf.width / 2
        y = height / 2 - pixbuf.height / 2
        window.draw_pixbuf(style.fg_gc(0), pixbuf,
          0, 0, x, y, pixbuf.width, pixbuf.height, 0, 0, 0)
      end
      true
    end

    (instance_methods - superclass.instance_methods) \
      .grep(/=$/).map { |i| i.chop! } \
      .each do |attr|
        alias_method "get_#{attr}", "#{attr}" if method_defined?("#{attr}")
        alias_method "set_#{attr}", "#{attr}="
      end
  end
end
