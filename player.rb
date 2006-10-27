#!/usr/bin/env ruby

require 'gtkmplayerembed'

class Window < Gtk::Window
  def initialize
    super
    set_title('Gtk::MPlayerEmbed')
    set_default_size(400, 300)
    signal_connect('delete-event') do
      @mplayer.kill_thread
      Gtk.main_quit
    end

    vbox = Gtk::VBox.new
    self << vbox

    @mplayer = Gtk::MPlayerEmbed.new
    @mplayer.fullscreen_size = [ 1024, 768 ]
    @mplayer.bg_logo = File.join(File.dirname(__FILE__), 'mplayer.png')
    @mplayer.bg_stripes = true
    @mplayer.signal_connect('fullscreen_toggled') do |mplayer, fullscreen|
      vbox.reorder_child(@mplayer, 0) if not fullscreen
    end
    @mplayer.signal_connect('realize') do
      @mplayer.play(ARGV)
    end unless ARGV.empty?
    vbox << @mplayer

    hbox = Gtk::HBox.new(false, 4)
    hbox.border_width = 6
    vbox.pack_start(hbox, false)

    button = Gtk::Button.new
    button << Gtk::Image.new(Gtk::Stock::OPEN, Gtk::IconSize::MENU)
    button.signal_connect('clicked') do
      dialog = Gtk::FileChooserDialog.new("Open File", self,
        Gtk::FileChooser::ACTION_OPEN, nil,
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
        [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT])
      dialog.select_multiple = true
      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        @mplayer.play(dialog.filenames)
      end
      dialog.destroy
    end
    hbox.pack_start(button, false)

    button = Gtk::Button.new
    button << Gtk::Image.new(Gtk::Stock::MEDIA_PAUSE, Gtk::IconSize::MENU)
    button.signal_connect('clicked') do
      @mplayer.pause
    end
    hbox.pack_start(button, false)

    button = Gtk::Button.new
    button << Gtk::Image.new(Gtk::Stock::MEDIA_STOP, Gtk::IconSize::MENU)
    button.signal_connect('clicked') do
      @mplayer.stop
    end
    hbox.pack_start(button, false)

    entry = Gtk::Entry.new
    entry.text = 'Enter a command'
    @clear = true
    @sid = entry.signal_connect('enter-notify-event') do
      if @clear
        entry.text = ''
        @clear = false
      end
      entry.grab_focus
    end
    entry.signal_connect('activate') do
      @mplayer.send_command entry.text
    end
    hbox << entry

    show_all
  end
end

Window.new
Gtk.main
