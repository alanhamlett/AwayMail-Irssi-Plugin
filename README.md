## AwayMail IRC Plugin for Irssi
Sends email notification(s) when someone types your name or sends you a private msg. Hint: use with screen_away.pl.

### Installation
Put the plugin file in your scripts directory.

```
git clone git://github.com/alanhamlett/AwayMail-Irssi-Plugin.git
cp AwayMail-Irssi-Plugin/awaymail.pl ~/.irssi/scripts/
ln -s ~/.irssi/scripts/awaymail.pl ~/.irssi/scripts/autorun/awaymail.pl
```

### Configuration
Open irssi and configure the plugin options.

```
screen irssi
/load awaymail.pl
/help awaymail
```

### Usage
Set yourself away or use the screen_away.pl plugin.

```
/away I am away. Highlight or PM me and I will be emailed with your message.
```

The next time someone says your nick or sends you a private message, their messages will be emailed to you.

### Download
<https://github.com/alanhamlett/AwayMail-Irssi-Plugin/tarball/master>

### Authors and Contributors
"Alan Hamlett" \<alan.hamlett@gmail.com> @alanhamlett

### Project Page
<http://alanhamlett.github.com/AwayMail-Irssi-Plugin>

### License
Released under the [MIT license](http://opensource.org/licenses/mit-license.php).
