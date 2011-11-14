AwayMail-Irssi-Plugin
====================

Sends a email(s) via SMTP with optional SSL to an email address when someone types your name or sends you a private msg. Hint: use with screen_away.pl.

Installation
------------

Put the plugin file in your scripts directory.

    git clone git://github.com/alanhamlett/jQuery-PicasaGallery.git
    cp AwayMail-Irssi-Plugin/awaymail.pl ~/.irssi/scripts/
    ln -s ~/.irssi/scripts/awaymail.pl ~/.irssi/scripts/autorun/awaymail.pl

Configuration
-------------

Open irssi and configure the plugin options.

    irssi
    /load awaymail.pl
    /help awaymail

Usage
-----

Set yourself away or use the screen_away.pl plugin.

    /away I am away. Hilight or PM me and I will be emailed your message.

The next time someone says your nick or sends you a private message, their messages will be emailed to you.

Download
--------

<https://github.com/alanhamlett/jQuery-PicasaGallery/tarball/master>

Project Page
------------

<https://github.com/alanhamlett/AwayMail-Irssi-Plugin>

License
-------

Released under the [MIT license](http://opensource.org/licenses/mit-license.php).

