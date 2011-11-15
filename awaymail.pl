use strict;
use vars qw($VERSION %IRSSI);

use Irssi qw(
	settings_get_bool
	settings_get_str
	settings_set_bool
	settings_set_str
);
$VERSION = '2.00';
%IRSSI = (
    authors     => 'Alan Hamlett',
    contact     => 'alan.hamlett@gmail.com',
    url         => 'http://ahamlett.com/',
    name        => 'Away Mail',
    description => 'Sends an email via SMTP with optional SSL to an email address when someone types your name or sends you a private msg. Hint: use with screen_away.pl',
    license     => 'GNU General Public License',
    changed     => 'Fri Jul  8 18:09:04 CDT 2011',
);

# Copyright 2011 Alan Hamlett <alan.hamlett@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

my $help = "
AWAYMAIL

Irssi Plugin. Sends an email notification when someone types your name or sends you a private message. Hint: use with screen_away.pl.

Usage:

 put this script in your scripts directory ( usually ~/.irssi/scripts/ )
 and link to it from your autorun directory ( cd ~/.irssi/scripts/autorun; ln -s ../awaymail.pl awaymail.pl )
 then in irssi load it with
  /SCRIPT LOAD awaymail.pl
 to see this help type
  /HELP awaymail

Required Perl Modules:

 Net::SMTP
 Net::SMTP::SSL ( if awayamail_ssl ON )
 MIME::Base64
 Authen::SASL

Available settings:

 /set awaymail_to <string>              - email address which will receive the notification email. ( Ex: you\@gmail.com )
 /set awaymail_server <string>          - SMTP server address. ( Ex: smtp.gmail.com )
 /set awaymail_port <number>            - port number of the SMTP server. Default is 465. ( Ex: 25 )
 /set awaymail_user <string>            - username of a user that can send email through the SMTP server. ( Ex: you\@gmail.com )
 /set awaymail_pass <string>            - password for SMTP user. ( Ex: your gmail password )
 /set awaymail_alwaysnotify <ON|OFF>    - if ON will send notification emails even when user is not away. Default is OFF.
 /set awaymail_delaymins <number>       - won't send a notification email if one was already sent within set number minutes. Default is 10.
 /set awaymail_ssl <ON|OFF>             - use or don't use SSL when connecting to SMTP server. Default is ON.

";

our %awaymail_buffer = ();
our $awaymail_default_delay = 10; # minimum number of minutes between sending emails
our $awaymail_timeout = 10; # number seconds between checking if the buffer should be emailed

Irssi::theme_register([
	'awaymail_loaded', '%R>>%n %_AwayMail:%_ Loaded $0 version $1' . "\n" . '%R>>%n %_AwayMail:%_ type /HELP AWAYMAIL for configuration information',
	'awaymail_sent', '%R>>%n %_AwayMail:%_ Sent awaymail',
	'awaymail_error', '%R>>%n %_AwayMail:%_ $0',
]);

sub awaymail_check_required_modules {
	if(settings_get_bool('awaymail_ssl')) { # SSL is turned on so check for required modules
		unless(eval "use Net::SMTP::SSL; 1") {
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Net::SMTP::SSL must be installed");
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
			return 0;
		}
		unless(eval "use MIME::Base64; 1") {
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module MIME::Base64 must be installed");
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
			return 0;
		}
		unless(eval "use Authen::SASL; 1") {
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Authen::SASL must be installed");
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
			return 0;
		}
	}
	else {
		unless(eval "use Net::SMTP; 1") {
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Net::SMTP must be installed");
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN and re-load this script");
			return 0;
		}
	}
	return 1;
}

sub awaymail_handle_timeout {
	# this gets called every $awaymail_timeout seconds to check if delay has passed and we have saved messages to be emailed
	my($data, $server) = @_;
	my $delaymins = settings_get_str('awaymail_delaymins');
	$delaymins =~ s/\D//g;
	$delaymins = $awaymail_default_delay unless $delaymins;
	if(keys %awaymail_buffer > 0 && settings_get_str('awaymail_lastsent') + $delaymins * 60 < time) {
		my $subject = "AwayMail Irssi: Multiple messages";
		my $body;
		foreach my $msg (keys %awaymail_buffer) {
			$body .= "__________________________________________________\n";
			$body .= "$msg\n\n" . $awaymail_buffer{$msg} . "\n";
			$body .= "__________________________________________________\n\n";
		}
		%awaymail_buffer = ();
		awaymail_send($subject, $body);
	}
	return 0;
}

sub awaymail_handle_print_text {
	my($dest, $text, $stripped) = @_;
	# only continue if:
	# - we are away or awaymail_alwaysnotify is ON
	# - messsage is public (MSGLEVEL_PUBLIC) and triggers channel activity (!MSGLEVEL_NO_ACT)
	# - our nick is found in the message with a non-word character before and after
	if($dest->{level} & MSGLEVEL_PUBLIC && !($dest->{level} & MSGLEVEL_NO_ACT) && (settings_get_bool('awaymail_alwaysnotify') || $dest->{server}->{usermode_away})) {
		my $me = $dest->{server}->{nick};
		if($stripped =~ /\W$me\W/i || $stripped =~ /\W$me$/i) { # make sure someone said your nick and not just a word containing your nick
			$stripped =~ /<\s*([^>]+)\s*>/;
			my $nick = $1;
			my $footer = "";
			# filter newlines because they can interfere with SMTP
			if($nick =~ s/[\r\n]//g) {
				$footer .= "\n\n( Newlines were filtered from user's nick, probably because of 32bit characters )";
			}
			if($stripped =~ s/[\r\n]//g) {
				$footer .= "\n\n( Newlines were filtered from user's message, probably because of 32bit characters )";
			}
			my $subject = "AwayMail Irssi: New hilight from $nick";
			my $body = "$nick said your name in " . $dest->{server}->{address} . " " . $dest->{target} . "\n\n" . $stripped . $footer;
			awaymail_process($subject, $body);
		}
	}
	return 0;
}

sub awaymail_handle_message_private {
	my ($server, $msg, $nick, $address) = @_;
	if(settings_get_bool('awaymail_alwaysnotify') || $server->{usermode_away}) { # we are away or awaymail_alwaysnotify is ON
		my $footer = "";
		# filter newlines because they can interfere with SMTP
		if($nick =~ s/[\r\n]//g) {
			$footer .= "\n\n( Newlines were filtered from user's nick, probably because of 32bit characters )";
		}
		if($msg =~ s/[\r\n]//g) {
			$footer .= "\n\n( Newlines were filtered from user's message, probably because of 32bit characters )";
		}
		my $subject		= "AwayMail Irssi: New pm from $nick";
		my $body		= "You have a new pm from " . $nick . " in server " . $server->{address} . "\n\n" . $msg . $footer;
		awaymail_process($subject, $body);
	}
	return 0;
}

sub awaymail_process {
	my($subject, $body) = @_;
	my $delaymins = settings_get_str('awaymail_delaymins');
	$delaymins =~ s/\D//g;
	$delaymins = $awaymail_default_delay unless $delaymins;
	if(settings_get_str('awaymail_lastsent') + $delaymins * 60 < time) {
		# the set number of minutes has passed since the last email was sent
		awaymail_send($subject, $body);
	} else {
		# save message to be sent with other messages in one email after delay has passed
		awaymail_save($subject, $body);
	}
}

sub awaymail_save {
	my($subject, $body) = @_;
	$body =~ s/\n\n/\n/g;
	$awaymail_buffer{$subject} = $awaymail_buffer{$subject} ? $awaymail_buffer{$subject} . "\n\n" . $body : $body;
}

sub awaymail_send {
	my($subject, $body) = @_;
	my $to			= settings_get_str('awaymail_to');
	my $from		= settings_get_str('awaymail_from');
	my $server		= settings_get_str('awaymail_server');
	my $port		= settings_get_str('awaymail_port');
	my $username		= settings_get_str('awaymail_user');
	my $password		= settings_get_str('awaymail_pass');
	if($to && $server && $port =~ /^\d+$/ && $username && $password) {
		settings_set_str("awaymail_lastsent", time);
		if(!$from) {
			$from		= $to;
			settings_set_str("awaymail_from", $to);
		}
		my $smtp	= settings_get_bool('awaymail_ssl') ? Net::SMTP::SSL->new($server, Port => $port) : Net::SMTP->new($server, Port => $port);
		if($smtp) {
			$smtp->auth($username, $password);
			$smtp->mail($from);
			$smtp->to($to);
			$smtp->data();
			$smtp->datasend("To: $to\r\nFrom: $from\r\nSubject: $subject\r\n\r\n$body\r\n");
			$smtp->dataend();
			if($smtp->ok()) {
				Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_sent');
			}
			else {
				Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Failed to send the email");
			}
			$smtp->quit();
		}
		else {
			Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Could not connect to SMTP server");
		}
	}
	else {
		Irssi::print($help, MSGLEVEL_CLIENTCRAP);
	}
}

sub awaymail_reset_time {
	%awaymail_buffer = ();
	settings_set_str('awaymail_lastsent', "0");
}

# Register user settings
Irssi::settings_add_str('awaymail', 'awaymail_to', "");
Irssi::settings_add_str('awaymail', 'awaymail_from', "");
Irssi::settings_add_str('awaymail', 'awaymail_server', "");
Irssi::settings_add_str('awaymail', 'awaymail_port', "465");
Irssi::settings_add_str('awaymail', 'awaymail_user', "");
Irssi::settings_add_str('awaymail', 'awaymail_pass', "");
Irssi::settings_add_bool('awaymail', 'awaymail_alwaysnotify', 0);
Irssi::settings_add_str('awaymail', 'awaymail_delaymins', "$awaymail_default_delay");
Irssi::settings_add_bool('awaymail', 'awaymail_ssl', 1);

# Register script settings
Irssi::settings_add_str('awaymail', 'awaymail_lastsent', "0");

return 1 unless awaymail_check_required_modules();

# Register signal handlers
Irssi::timeout_add($awaymail_timeout*1000, "awaymail_handle_timeout", "");
Irssi::signal_add_last('print text', 'awaymail_handle_print_text');
Irssi::signal_add_last('message private', 'awaymail_handle_message_private');
Irssi::signal_add_last('away mode changed', 'awaymail_reset_time');

# Overwrite the help command for awaymail
Irssi::command_bind('help', sub {
	if(lc $_[0] eq 'awaymail') {
		Irssi::print($help, MSGLEVEL_CLIENTCRAP);
		Irssi::signal_stop;
	}
});

Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_loaded', $IRSSI{name}, $VERSION);

