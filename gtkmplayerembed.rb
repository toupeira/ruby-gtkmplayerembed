=begin

  $Id$

=end

require 'gtk2'

module Gtk
  class MPlayerEmbed < EventBox
    INPUT_PATHS = [ ENV['HOME'] + '/.mplayer/input.conf',
                    '/etc/mplayer/input.conf', ]
    KEYCODES = {
      'space'     => 32,
      'bs'        => 65288,
      'enter'     => 65293,
      'esc'       => 65307,
      'pgup'      => 65365,
      'pgdwn'     => 65366,
      'ins'       => 65379,
      'kp_enter'  => 65421,
      'kp_ins'    => 65438,
      'kp_del'    => 65439,
      'kp_dec'    => 65454,
      'del'       => 65535,
    }

    attr_accessor :mplayer_path
    attr_accessor :mplayer_options

    def initialize(path='mplayer', options=nil)
      @mplayer_path = path
      @mplayer_options = options
      @bindings = {}

      load_bindings

      super()
      modify_bg(Gtk::STATE_NORMAL, style.black)
      signal_connect('key-press-event') do |w, event|
        puts "#{Gdk::Keyval.to_name(event.keyval)} => #{event.keyval}"
        case command = @bindings[event.keyval]
        when 'vo_fullscreen': fullscreen
        else
            thread :run, command
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

    def fullscreen
      if @window and toplevel == @window
        reparent(@old_widget)
        @window.destroy
      else
        @old_widget = parent
        @window = Gtk::Window.new
        @window.fullscreen
        @window.show_all
        reparent(@window)
      end
      grab_focus
    end

    def thread(*args)
      if @thread and not args.empty?
        @thread.send(*args)
      else
        @thread
      end
    end

    def play(*files)
      puts 'playing!!!'
      open_thread unless thread :alive?
      thread :run, :loadfile => files
    end

    def stop
      thread :run, :quit
    end

    def kill
      thread :kill
    end

    [ :pause, :mute, :switch_audio ].each do |cmd|
      define_method(cmd) { thread :run, cmd }
    end

  private

    def load_bindings
      if file = INPUT_PATHS.find { |f| File.readable? f }
        File.readlines(file).each do |line|
          if line =~ /^([^# ]+) (.+)$/
            if $1.size == 1
              keyval = Gdk::Keyval.from_unicode $1
            elsif not keyval = KEYCODES[$1.downcase]
              keyval = Gdk::Keyval.from_name $1.capitalize
            end
            @bindings[keyval] = $2 if keyval > 0
          end
        end
      end
    end

    def open_thread
      return if thread :alive?

      x = @socket.allocation.width
      y = @socket.allocation.height
      cmd = "#{@mplayer_path} -slave -idle -quiet -identify " +
            "-wid #{@socket.id} -geometry #{x}x#{y} #{@mplayer_options}"
      puts "opening slave with #{cmd}"

      @thread = PlayerThread.new(cmd, @aspect)
      @thread.signal_connect('aspect') do |thread, ratio|
        @aspect.ratio = ratio
      end
      @thread.signal_connect('stopped') do
        @thread = nil
      end
    end

    class PlayerThread < GLib::Object
      type_register
      signal_new 'aspect',
        GLib::Signal::RUN_FIRST, nil, GLib::Type['void'], Float
      signal_new 'stopped',
        GLib::Signal::RUN_FIRST, nil, GLib::Type['void']

      def initialize(command, aspect)
        super()
        @answers = {}
        @aspect = aspect
        @pipe = IO.popen(command, 'a+')
        @thread = Thread.new { slave }
      end

      def slave
        width = height = 0
        until @pipe.eof? or @pipe.closed?
          if @aspect.nil? or @aspect.destroyed?
            kill
            break
          end
          line = @pipe.readline.chomp
          if match = /^([a-z_]+)=(.+)$/i.match(line)
            key, value = match.captures
            case key
            when 'ID_VIDEO_WIDTH'
              width = value.to_i if value
            when 'ID_VIDEO_HEIGHT'
              if width > 0 and (height = value.to_f) > 0
                puts "changing aspect ratio to #{width / height}"
                signal_emit 'aspect', width / height
              end
            when 'ID_VIDEO_ASPECT'
              unless (ratio = value.to_f).zero?
                puts "changing aspect ratio to #{ratio}"
                signal_emit 'aspect', ratio
              end
            when /^ANS_([a-z_]+)$/i
              puts 'sali'
              @answers[key] = value
              puts value
            end
          end
        end
      ensure
        @pipe.close if @pipe
        @pipe = nil
        puts 'Thread is done.'
        signal_emit 'stopped'
      end

      def alive?
        @pipe.flush and true rescue false
      end

      def kill
        puts 'killing'
        Process.kill 'INT', @pipe.pid if alive?
        @thread.join if @thread
        @thread = nil
        @pipe = nil
      end

      def run(cmd)
        if cmd.is_a? Hash and cmd.values.first.is_a? Array
          args = cmd.values.first.map { |a| a.inspect}
          command = "#{cmd.keys.first} #{args.join ' '}"
          #command, args = cmd.entries.first
          open if cmd[:open] and not alive?
        else
          command = cmd
        end
        if alive?
          puts "sending #{command.inspect}"
          @pipe.write "#{command}\n"
        end
      end

    private
      def signal_do_aspect(aspect) end
      def signal_do_stopped() end
    end
  end

  def self.idle
    Gtk.idle_add do
      yield
      false
    end
  end
end
