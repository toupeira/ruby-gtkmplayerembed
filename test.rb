#!/usr/bin/env ruby

require 'gtkmplayerembed'

class Window < Gtk::Window
  def initialize
    super
    set_default_size(400, 300)
    signal_connect('delete-event') do
      @mplayer.kill
      Gtk.main_quit
    end
    signal_connect('map-event') do
      @mplayer.play '/mnt/sda3/movies/Three Kings (1999).ogm'
    end
    #signal_connect('key-press-event') do |win, event|
    #  @mplayer.event(event)
    #end

    vbox = Gtk::VBox.new
    self << vbox

    @mplayer = Gtk::MPlayerEmbed.new
    vbox << @mplayer

    hbox = Gtk::HBox.new
    hbox.height_request = 24
    vbox.pack_start(hbox, false)

    entry = Gtk::Entry.new
    entry.signal_connect('activate') do
      @mplayer.send_command entry.text
    end
    hbox << entry

    button = Gtk::Button.new
    button << Gtk::Image.new(Gtk::Stock::OPEN, Gtk::IconSize::MENU)
    button.signal_connect('clicked') do
      dialog = Gtk::FileChooserDialog.new("Open File", self,
        Gtk::FileChooser::ACTION_OPEN, nil,
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
        [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT])
      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        @mplayer.play(dialog.filename)
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
      @mplayer.kill
    end
    hbox.pack_start(button, false)

    show_all
  end
end

Window.new
Gtk.main
