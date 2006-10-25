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
    signal_new 'playlist_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Array
    signal_new 'length_changed',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Integer
    signal_new 'fullscreen_toggled',
      GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], TrueClass

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

    attr_accessor :mplayer_path, :mplayer_options,
                  :fullscreen_width, :fullscreen_height,
                  :bg_color, :bg_logo, :bg_stripes, :bg_stripes_color
    attr_reader :config, :file, :playlist

    def initialize(path='mplayer', options=nil)
      @mplayer_path = path
      @mplayer_options = options

      @fullscreen_width = Gdk::Screen.default.width
      @fullscreen_height = Gdk::Screen.default.height

      @bg_color = Gdk::Color.parse('black')
      @bg_stripes_color = Gdk::Color.parse('#333')

      @file = {}
      @answers = {}
      @bindings = {}
      load_bindings

      super()
      modify_bg(Gtk::STATE_NORMAL, style.black)
      set_can_focus(true)
      set_size_request(10, 10)

      signal_connect('realize') { @aspect.hide }
      signal_connect('expose-event') { draw_background }
      signal_connect('enter-notify-event') { grab_focus }
      signal_connect('button-press-event') do |w, event|
        toggle_fullscreen if event.button == 3
      end
      signal_connect('key-press-event') do |w, event|
        puts "#{Gdk::Keyval.to_name event.keyval} => #{event.keyval}" if $DEBUG
        case command = @bindings[event.keyval]
        when Proc
          command.call
        when 'vo_fullscreen'
          toggle_fullscreen
        when /^vo_ontop/
          toplevel.keep_above = true if toplevel
        else
          send_command(command) if command
        end
      end

      @aspect = Gtk::AspectFrame.new(nil, 0.5, 0.5, 16/9.0, false)
      @aspect.shadow_type = Gtk::SHADOW_NONE
      self << @aspect

      @socket = Gtk::Socket.new
      @socket.modify_bg(Gtk::STATE_NORMAL, style.black)
      @aspect << @socket
    end

    def fullscreen?
      @fs_window and toplevel == @fs_window
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

        screenx = Gdk::Screen.default.width
        screeny = Gdk::Screen.default.height
        width = @fullscreen_width || screenx
        height = @fullscreen_height || screeny
        width = [0, [screenx, width].min].max
        height = [0, [screeny, height].min].max
        align.set_right_padding(screenx - width)
        align.set_bottom_padding(screeny - height)

        @fs_window.show_all
        reparent(align)
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

    def show_text(text, time=2000)
      send_command :osd_show_text => [ text, time ], :pausing => 'keep'
    end

    def kill_thread
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
      @file[:ratio] = ratio
      @aspect.ratio = ratio
    end

    def bg_color=(color)
      color = Gdk::Color.parse(color) unless color.is_a? Gdk::Color
      @bg_color = color
    end

    def bg_logo=(logo)
      logo = Gdk::Pixbuf.new(logo) unless logo.is_a? Gdk::Pixbuf
      @bg_logo = logo
    end

    def bg_stripes_color(color)
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
              open_thread
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
        puts "sending #{command.inspect}"
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

    def signal_do_stopped
      puts 'thread stopped.'
      @pipe = nil
      @thread = nil
      @file = {}

      @aspect.hide
      toggle_fullscreen if fullscreen?
    end

    def signal_do_file_changed(file) end
    def signal_do_playlist_changed(playlist) end
    def signal_do_length_changed(length) end
    def signal_do_fullscreen_toggled(fullscreen) end

    def format_time(time)
      time = time.to_i
      "%02d:%02d:%02d" % [time / 3600, (time % 3600) / 60, time % 60]
    end

    def load_bindings
      if file = INPUT_PATHS.find { |f| File.readable? f }
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

    def add_binding(key, command=nil, &block)
      if key.size == 1
        keyval = Gdk::Keyval.from_unicode(key)
      elsif name = KEYNAMES[key.downcase]
        keyval = Gdk::Keyval.from_name(name)
      elsif (keyval = Gdk::Keyval.from_name(key)).zero?
        keyval = Gdk::Keyval.from_name(key.capitalize)
      end
      command = block ? block : command
      @bindings[keyval] = command if keyval > 0
    end

    def thread_alive?
      @thread and @pipe.flush and true rescue false
    end

    def open_thread(options=nil)
      return if thread_alive?
      @aspect.show_all
      x = @socket.allocation.width
      y = @socket.allocation.height
      cmd = "#{@mplayer_path} -slave -quiet -identify " +
            "-wid #{@socket.id} -geometry #{x}x#{y} " +
            "#{options} #{@mplayer_options}"
      puts @pipe
      @thread = Thread.new { slave_reader(cmd) }
    end

    def slave_reader(command)
      @answers = {}
      puts "opening slave with #{command}"
      @pipe = IO.popen(command, 'a+')
      until @pipe.eof? or @pipe.closed?
        if @aspect.nil? or @aspect.destroyed?
          kill_slave
          break
        end
        line = @pipe.readline.chomp
        if match = /^([a-z_]+)=(.+)$/i.match(line)
          key, value = match.captures
          case key
          when 'ID_FILENAME'
            @file = { :path => value, :width => 0 }
          when 'ID_LENGTH'
            @file[:length] = value.to_i
            signal_emit 'length_changed', @file[:length]
          when 'ID_VIDEO_WIDTH'
            @file[:width] = value.to_i if value
          when 'ID_VIDEO_HEIGHT'
            if @file[:width] > 0 and (@file[:height] = value.to_f) > 0
              Gtk.idle { self.ratio = @file[:width] / @file[:height] }
            end
          when 'ID_VIDEO_ASPECT'
            unless (ratio = value.to_f).zero?
              puts "changing aspect ratio to #{ratio}"
              Gtk.idle { self.ratio = ratio }
            end
          when /^ID_([a-z_]+)$/i
            if value
              @file[$1.downcase.to_sym] = value.to_i > 0 ? value.to_i : value
            end
          when /^ANS_([a-z_]+)$/i
            @answers[$1] = value
          end
        end
      end
    rescue Exception => exc
      Gtk.idle { raise exc }
    ensure
      signal_emit 'stopped'
    end

    def draw_background
      return if thread_alive?

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
  end
end
