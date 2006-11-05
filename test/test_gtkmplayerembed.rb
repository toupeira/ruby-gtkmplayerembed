require 'test/unit'
require 'gtkmplayerembed'

class MPlayerEmbedTest < Test::Unit::TestCase
  def test_simple
    mplayer = Gtk::MPlayerEmbed.new('/usr/bin/mplayer', '-foo bar')

    assert_kind_of Gtk::Widget, mplayer
    assert_equal '/usr/bin/mplayer', mplayer.mplayer_path
    assert_equal '-foo bar', mplayer.mplayer_options
    assert_equal [ Gdk::Screen.default.width, Gdk::Screen.default.height ],
                 mplayer.fullscreen_size
    assert_equal false, mplayer.fullscreen?
  end
end
