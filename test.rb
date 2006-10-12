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
    signal_connect('key-press-event') do |win, event|
      @mplayer.event(event)
    end

    vbox = Gtk::VBox.new
    modify_bg(Gtk::STATE_NORMAL, style.black)
    self << vbox

    @mplayer = Gtk::MPlayerEmbed.new
    vbox << @mplayer

    hbox = Gtk::HBox.new(true)
    vbox.pack_start(hbox, false)

    button = Gtk::Button.new(Gtk::Stock::OPEN)
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
    hbox << button

    button = Gtk::Button.new(Gtk::Stock::MEDIA_PAUSE)
    button.signal_connect('clicked') do
      @mplayer.pause
    end
    hbox << button

    button = Gtk::Button.new(Gtk::Stock::MEDIA_STOP)
    button.signal_connect('clicked') do
      @mplayer.kill
    end
    hbox << button

    show_all
  end
end

Window.new
Gtk.main
