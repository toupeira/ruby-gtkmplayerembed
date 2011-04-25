# Gtk::MPlayerEmbed

## Overview

This is a widget for embedding MPlayer into Ruby/GTK applications using the
XEMBED protocol.

The widgets embeds MPlayer in a `Gtk::Socket` and an `AspectFrame` to constrain
it to an aspect ratio, which is automatically detected from MPlayer's output.
Additionally, the widget is wrapped in a `EventBox` to enable fancy splash screens.

Keyboard bindings are automatically read from the MPlayer config file if it can be
found. The menu is disabled by default, since you can't use the arrow keys to
navigate it. But you may add additional bindings and enable it by passing custom
command-line arguments.

Fullscreen mode is emulated by creating a new window and reparenting the widget to
it. When switching back again, the widget may get wrongly packed in the former parent
container. Use the `fullscreen-toggled` signal to rectify this, or overwrite the
`toggle_fullscreen` method for more complex situations.

## Usage

See the sample player and the RDoc documentation for some examples.

## Bugs

I only tested this on Linux with Ruby 1.8.5, Ruby/GTK 0.15 and GTK 2.10.
MPlayer video output only works correctly with xv, sdl creates another window,
and x11, gl and gl2 don't scale to the available space.

If the Ruby interpreter dies because of a GTK crash or something, an
MPlayer instance may be left running in the background.

## License

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2 as
published by the Free Software Foundation.

## Author

Markus Koller <markus-koller@gmx.ch>

http://github.com/toupeira

