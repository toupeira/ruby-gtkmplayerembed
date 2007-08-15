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

class String
  unless method_defined? :escape_shell
    def escape_shell
      "\"#{self.gsub '"', '\\"'}\""
    end
  end
end

module Gtk #:nodoc:
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

    # Paths to be searched for MPlayer keybindings.
    INPUT_PATHS = [ "#{ENV['HOME']}/.mplayer/input.conf",
                    "/etc/mplayer/input.conf" ]

    # Some keyname mappings from MPlayer to GTK schemes.
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

    # Information about the currently playing file.
    attr_reader :current

    # List of currently playing files.
    attr_reader :playlist

    # Path to the MPlayer executable.
    attr_accessor :mplayer_path

    # MPlayer command-line options.
    attr_accessor :mplayer_options

    # The output size for fullscreen mode.
    attr_accessor :fullscreen_size

    # The background color.
    attr_accessor :bg_color

    # The image used for the background logo.
    attr_accessor :bg_logo

    # Draw background stripes.
    attr_accessor :bg_stripes

    # The color used for the background stripes.
    attr_accessor :bg_stripes_color

    def self.parse_property(line)
      if line =~ /^([a-z_ ]+)[=:](.+)$/i
        key, value = $1.strip, $2.strip

        case key
        when /^ID_(\w+)$/
          key = $1
          key = $1 if key =~ /^VIDEO_(WIDTH|HEIGHT)$/
        when 'Language'
          value = value[/^([^\[]+)/, 1] || value
        when /^Selected (audio|video) codec$/
          key = "#{$1}_codec"
          value = value[/\((.*)\)/, 1] || value
        else
          return nil
        end

        key = key.downcase.intern
        value = value.to_i if value =~ /^\d+$/
        value = value.to_f if value =~ /^\d+\.\d+$/

        if value == 0 or value.is_a?(String) && value.empty?
          return nil
        else
          return [ key, value ]
        end
      end
    end

    def self.identify(file)
      file = file.escape_shell
      debug "identifying #{file}"
      command = "mplayer -quiet -identify -vo null -ao null -frames 0 #{file}"
      @pipe = IO.popen(command, 'r')

      @info = {}
      until @pipe.eof?
        if property = parse_property(@pipe.readline)
          key, value = property
          @info[key] = value
        end
      end
      @info
    end

    # Create a new instance. By default, 'mplayer' will be searched for in
    # <tt>$PATH</tt>, use <tt>path</tt> to specify an explicit executable
    # and <tt>options</tt> to pass command-line arguments.
    def initialize(path='mplayer', options=nil)
      @mplayer_path = path
      @mplayer_options = options

      @thread = @pipe = @fs_window = nil
      @fullscreen_size = [ Gdk::Screen.default.width,
                           Gdk::Screen.default.height ]

      @bg_color = Gdk::Color.parse('black')
      @bg_stripes_color = Gdk::Color.parse('#333')

      @current = {}
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

      # Process key events using the configured bindings.
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

    # Play on or more files, pass a String or an Array.
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

    # Quit MPlayer.
    def stop
      send_command :quit
    end

    # Play the next movie in the playlist.
    def next(step=1)
      send_command :pt_step => step
    end

    # Play the previous movie in the playlist.
    def previous(step=1)
      send_command :pt_step => -step
    end

    # Seek forward or backward, pass <tt>step</tt> as seconds.
    def seek(step)
      send_command :seek => step, :pausing => 'keep'
    end

    # Toggle pause.
    def pause
      send_command :pause
    end

    # Toggle audio output.
    def mute
      send_command :mute
    end

    # Get the aspect ratio.
    def ratio
      @aspect.ratio
    end

    # Set the aspect ratio.
    def ratio=(ratio)
      debug "changing aspect ratio to #{ratio}"
      @current[:ratio] = ratio
      @aspect.ratio = ratio
    end

    # Set the output size for fullscreen mode. The video will be placed in the
    # upper left corner of the screen.
    undef :fullscreen_size=; def fullscreen_size=(*size)
      size.flatten!
      if size.size == 2 and size.all? { |i| i.is_a? Integer }
        width =  [ [ size[0], 5 ].max, Gdk::Screen.default.width ].min
        height = [ [ size[1], 5 ].max, Gdk::Screen.default.height ].min
        @fullscreen_size = [ width, height ]
      else
        raise ArgumentError, "invalid size"
      end
    end

    # Returns true if the player is wrapped in a fullscreen window
    def fullscreen?
      @fs_window.is_a? Gtk::Window and toplevel == @fs_window
    end

    # Toggle fullscreen mode if needed
    def fullscreen=(status)
      toggle_fullscreen unless fullscreen? == status
    end

    # Toggle fullscreen mode
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

    # Set the background color.
    undef :bg_color=; def bg_color=(color)
      color = Gdk::Color.parse(color) unless color.is_a? Gdk::Color
      modify_bg(Gtk::STATE_NORMAL, color)
      @socket.modify_bg(Gtk::STATE_NORMAL, color)
      @bg_color = color
    end

    # Set the background logo, pass either a filename or a <tt>Gdk::Pixbuf</tt>
    # directly.
    undef :bg_logo=; def bg_logo=(logo)
      logo = Gdk::Pixbuf.new(logo) unless logo.is_a? Gdk::Pixbuf
      @bg_logo = logo
    end

    # Set the color usd for the background stripes. Pass a color description
    # or a <tt>Gdk::Color</tt> directly.
    undef :bg_stripes_color=; def bg_stripes_color=(color)
      color = Gdk::Color.parse(color) unless color.is_a? Gdk::Color
      @bg_stripes_color = color
    end

    # Show text in the MPlayer OSD.
    def show_text(text, time=3000)
      send_command :osd_show_text => [ text, time ], :pausing => 'keep'
    end

    # Add a custom keybinding. <tt>key</tt> can either be a single character, a
    # <tt>Gdk</tt> keyname or one of the MPlayer keynames from <tt>KEYNAMES</tt>.
    # You can pass an MPlayer input command directly, or a block with a custom
    # action.
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

    # Send a command to the MPlayer thread.
    # See <tt>mplayer -input cmdlist</tt> for a list of all commands and
    # arguments, and the MPlayer documentation for their description.
    #
    # Commands can be specified either by Strings, Symbols, or as a Hash
    # with options.  Examples:
    #
    # send_command 'seek 10'
    #
    # send_command :pause
    #
    # send_command :loadfile => @path
    #
    # Arguments passed in a hash will be automatically escaped.
    # You can also pass <tt>:open => true</tt> to start MPlayer if
    # necessary.
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
              args = Array(value).map do |a|
                a.is_a?(String) ? a.escape_shell : a.inspect
              end.join(' ')
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

    # Send a command to the MPlayer thread and wait for an answer.
    # Pass the <tt>key</tt> returned by MPlayer. 
    def read_command(command, key)
      @answers.delete(key)
      send_command command, :pausing => 'keep'
      i = 0
      sleep 0.005 until @answers[key] or (i += 1) > 10
      @answers[key]
    end

    # Check if the MPlayer thread is still alive and responsive.
    def thread_alive?
      @thread and @pipe and @pipe.flush and true rescue false
    end

    # Kill the MPlayer thread forcibly.
    def kill_thread
      Process.kill 'INT', @pipe.pid if thread_alive?
      @thread.join if @thread
      @thread = nil
      @pipe = nil
    end

  private

    # Log a message in debug mode.
    def self.debug(message)
      puts "[Gtk::MPlayerEmbed::#{$$}] #{message}" if $DEBUG
    end

    def debug(message)
      MPlayerEmbed.debug(message)
    end

    # The <tt>stopped</tt> signal is fired after the MPlayer thread has
    # stopped. The @aspect is hidden so the splash screen can be drawn.
    def signal_do_stopped
      debug "#{@thread.inspect} stopped" if @thread
      @pipe = nil
      @thread = nil
      @current = {}

      @aspect.hide
      toggle_fullscreen if fullscreen?
    end

    # Reset file information.
    def signal_do_file_changed(file)
      @current = { :path => file }
    end

    # Gets fired when the file is fully loaded. <tt>properties</tt> contains
    # a hash with information about the current file collected from MPlayer's
    # output.
    def signal_do_properties_changed(properties) end

    # Gets fired when a new playlist was loaded. <tt>playlist</tt> contains
    # the list of current files.
    def signal_do_playlist_changed(playlist) end

    # Gets fired when a new length was detected. <tt>length</tt> contains
    # the length in seconds.
    def signal_do_length_changed(length) end

    # Gets fired after fullscreen mode was toggled. <tt>fullscreen</tt> contains
    # whether fullscreen mode is enabled.
    def signal_do_fullscreen_toggled(fullscreen) end

    # Format seconds for displaying.
    def format_time(time)
      time = time.to_i
      "%02d:%02d:%02d" % [time / 3600, (time % 3600) / 60, time % 60]
    end

    # Load the default bindings
    def load_bindings
      # Try to load bindings from the MPlayer configuration file
      if file = INPUT_PATHS.find { |f| File.readable? f }
        debug "reading bindings from #{file}"
        File.readlines(file).each do |line|
          if line =~ /^((?!MOUSE.*|.*menu.*)[^# ]+) (.+)$/
            add_binding($1, $2)
          end
        end
      end

      # Display some information when 'i' is pressed.
      add_binding('i') do
        next unless @current[:path]
        pos = format_time(read_command(:get_time_pos, 'TIME_POSITION'))
        length = format_time(@current[:length])
        percent = read_command(:get_percent_pos, 'PERCENT_POSITION')
        show_text "#{File.basename(@current[:path])}   #{pos} / #{length}   (#{percent}%)"
      end

      # Display the current time when 'c' is pressed.
      add_binding('c') do
        show_text Time.now.strftime('%T')
      end
    end

    # Run MPlayer in a thread, pass arguments with <tt>options</tt>.
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

    # Listen to MPlayer's output and collect information about the playing
    # files.
    def slave_reader(command)
      @answers = {}
      @pipe = IO.popen(command, 'a+')

      until @pipe.nil? or @pipe.closed? or @pipe.eof?
        if @aspect.nil? or @aspect.destroyed?
          # Exit if parent widget is destroyed.
          kill_slave
          break
        end

        line = @pipe.readline.chomp
        if line == 'Starting playback...'
          signal_emit('properties_changed', @current)
        elsif line =~ /^ANS_(\w+)$/
          # Collect responses from special commands.
          @answers[$1] = value
        elsif property = MPlayerEmbed.parse_property(line)
          # Collect file properties
          key, value = property
          @current[key] = value

          case key
          when :filename
            signal_emit 'file_changed', value
          when :length
            signal_emit 'length_changed', value
          when :video_height
            unless @current[:video_aspect]
              # Calculate fallback aspect ratio from width and height
              ratio = @current[:video_width] / @current[:video_height].to_f
              Gtk.idle { self.ratio = ratio }
            end
          when :video_aspect
            # Use requested aspect ratio
            Gtk.idle { self.ratio = value }
          end
        end
      end
    rescue Exception => exc
      Gtk.idle { raise exc }
    ensure
      signal_emit 'stopped'
    end

    # Draw the background splash screen, either just a blank color or a
    # full-blown striped logo.
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

    # Alias some getters and setters.
    (instance_methods - superclass.instance_methods) \
      .grep(/=$/).map { |i| i.chop! } \
      .each do |attr|
        alias_method "get_#{attr}", "#{attr}" if method_defined?("#{attr}")
        alias_method "set_#{attr}", "#{attr}="
      end
  end
end
