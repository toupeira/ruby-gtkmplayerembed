=begin

  $Id$

=end

require 'gtk2'

module Gtk
  def self.refresh
    Gtk.main_iteration while Gtk.events_pending?
  end

  def self.idle
    Gtk.idle_add do
      yield
      false
    end
  end

  class MPlayerEmbed < EventBox
    INPUT_PATHS = [ ENV['HOME'] + '/.mplayer/input.conf',
                    '/etc/mplayer/input.conf', ]
    KEYVALS = {
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

    ALIASES = {
      :play => :loadfile,
      :stop => :quit,
    }

    attr_accessor :mplayer_path
    attr_accessor :mplayer_options

    def initialize(path='mplayer', options=nil)
      @mplayer_path = path
      @mplayer_options = options
      @bindings = {}
      @answers = {}
      @commands = {}

      load_bindings
      load_commands

      super()
      modify_bg(Gtk::STATE_NORMAL, style.black)
      signal_connect('key-press-event') do |w, event|
        puts "#{Gdk::Keyval.to_name(event.keyval)} => #{event.keyval}"
        if command = @bindings[event.keyval]
          send_command(command)
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

    def method_missing(symbol, *args)
      symbol = ALIASES.fetch(symbol, symbol)
      if @commands.include? symbol
        range = @commands[symbol]
        if range.include? args.size
          puts "#{symbol} is fine"
          args = args.map { |i| i.inspect }.join ' '
          send_command("#{symbol} #{args}")
        else
          raise ArgumentError, "command #{symbol} takes #{range} arguments."
        end
      else
        super
      end
    end

    def send_command(command, open=true)
      open_slave if open and not slave_alive?
      puts "sending #{command.inspect}"
      @pipe.write "#{command}\n"
    end

  private

    def load_bindings
      if file = INPUT_PATHS.find { |f| File.readable? f }
        File.readlines(file).each do |line|
          if line =~ /^([^# ]+) (.+)$/
            if $1.size == 1
              keyval = Gdk::Keyval.from_unicode $1
            elsif not keyval = KEYVALS[$1.downcase]
              keyval = Gdk::Keyval.from_name $1.capitalize
            end
            @bindings[keyval] = $2 if keyval > 0
          end
        end
      end
    end

    def slave_alive?
      @pipe.flush and true rescue false
    end

    def load_commands
      pipe = IO.popen("#{@mplayer_path} -input cmdlist")
      pipe.readlines.each do |line|
        if match = /^([a-z_]+) +(.*)$/.match(line)
          args = match[2].split
          max = args.size
          min = args.find_all { |i| i[0, 1] != '[' }.size
          if methods.include? match[1]
            puts "#{match[1]} is an instance method of #{self.inspect}"
          elsif private_methods.include? match[1]
            puts "#{match[1]} is a private method of #{self.inspect}"
          end
          @commands[match[1].to_sym] = min..max
        end
      end
      pipe.close
    end

    def kill_slave
      @thread.kill if @thread
      if slave_alive?
        @thread.kill if @thread
        Process.kill 'TERM', @pipe.pid
        Process.waitpid @pipe.pid
        @pipe = nil
      end
    end

    def open_slave
      return if slave_alive?

      x = @socket.allocation.width
      y = @socket.allocation.height
      cmd = "#{@mplayer_path} -slave -idle -quiet -identify " +
            "-wid #{@socket.id} -geometry #{x}x#{y} #{@mplayer_options}"
      puts "opening slave with #{cmd}"

      @pipe = IO.popen(cmd, 'a+')
      @thread = Thread.new { slave_reader }
    end

    def slave_reader
      until @pipe.eof? or @pipe.closed?
        line = @pipe.readline.chomp
        if line =~ /^([A-Z_]+)=(.+)$/
          case $1
          when /^ANS_([a-z_]+)=(.+)$/
            @answers[$1] = $2
          when 'ID_VIDEO_WIDTH'
            @width = $2.to_f
          when 'ID_VIDEO_HEIGHT'
            @height = $2.to_f
            puts "changing aspect ratio to #{@width / @height}"
            Gtk.idle { @aspect.ratio = @width / @height } if @width
          when 'ID_VIDEO_ASPECT'
            unless (ratio = $2.to_f).zero?
              puts "changing aspect ratio to #{ratio}"
              Gtk.idle { @aspect.ratio = ratio }
            end
          end
        end
      end
    ensure
      @pipe.close if @pipe
      @pipe = nil
      puts 'Thread is done.'
    end
  end
end
