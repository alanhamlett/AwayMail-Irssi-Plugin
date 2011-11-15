use strict;
use vars qw($VERSION %IRSSI);

use Irssi qw(
	settings_get_bool
	settings_get_str
);
$VERSION = '1.01';
%IRSSI = (
    authors     => 'Alan Hamlett',
    contact     => 'alan.hamlett@gmail.com',
	url         => "http://uan.no-ip.com:8080/",
    name        => 'Away Mail',
    description => 'Sends an email via SMTP with SSL to an email address when someone types your name or sends you a private msg.',
    license     => 'Public Domain',
);

unless(eval "use Net::SMTP::SSL; 1") {
	Irssi::print("***** Away Mail: Perl module Net::SMTP::SSL must be installed");
	Irssi::print("***** Away Mail: Install it with CPAN and re-load this script");
	return;
}
unless(eval "use MIME::Base64; 1") {
	Irssi::print("***** Away Mail: Perl module MIME::Base64 must be installed");
	Irssi::print("***** Away Mail: Install it with CPAN and re-load this script");
	return;
}
unless(eval "use Authen::SASL; 1") {
	Irssi::print("***** Away Mail: Perl module Authen::SASL must be installed");
	Irssi::print("***** Away Mail: Install it with CPAN and re-load this script");
	return;
}

my $time;

sub handle_printtext {
	my($dest, $text, $stripped)	= @_;
	if($dest->{level} & MSGLEVEL_HILIGHT) { # this is a hilighted message
		my $subject		= "AwayMail Irssi Notification";
		my $header		= "Someone said your name in " . $dest->{"server"}->{"address"} . " " . $dest->{"target"} . "\n-------------\n";
		send_email($dest->{"server"}->{"usermode_away"}, $subject, $header, $stripped);
	}
}

sub handle_privatemsg {
	my ($server, $msg, $nick, $address) = @_;
	my $subject		= "AwayMail Irssi Notification";
	my $header		= "You have a new pm from " . $nick . " in server " . $server->{"address"} . "\n-------------\n";
	send_email($server->{"usermode_away"}, $subject, $header, $msg);
}

sub send_email {
	my($away, $subject, $header, $body)	= @_;
	my $delaymins	= settings_get_str('awaymail_delaymins');
	$delaymins		=~ s/\D//g;
	$delaymins		= 10 unless $delaymins;
	if($time + $delaymins * 60 < time) { # the set number of minutes has passed since the last email was sent
		my $alwaysnotify	= settings_get_bool('awaymail_alwaysnotify');
		if($alwaysnotify || $away) { # we are away or awaymail_alwaysnotify is set to YES
			my $to			= settings_get_str('awaymail_to');
			my $from		= settings_get_str('awaymail_from');
			my $server		= settings_get_str('awaymail_server');
			my $port		= settings_get_str('awaymail_port');
			my $username	= settings_get_str('awaymail_user');
			my $password	= settings_get_str('awaymail_pass');
			if(valid_email($to) && $server && $port =~ /^\d+$/ && $username && $password) {
				$time	= time;
				if(!valid_email($from)) {
					$from		= $to;
					Irssi::settings_set_str("awaymail_from", $to);
				}
				
				$subject	= filter_string($subject);
				$header		= filter_string($header);
				$body		= filter_string($body);
				my $content		= "$header$body";
				
				my $smtps = Net::SMTP::SSL->new($server, Port => $port);
				$smtps->auth($username, $password);
				$smtps->mail($from);
				$smtps->to($to);
				$smtps->data();
				$smtps->datasend("To: $to\r\nFrom: $from\r\nSubject: $subject\r\n\r\n$content\r\n");
				$smtps->dataend();
				if($smtps->ok()) {
					Irssi::print("***** Away Mail: Sent notification email to $to");
				}
				else {
					Irssi::print("***** Away Mail: Failed to send the email");
				}
				$smtps->quit();
			}
			else {
				Irssi::print("***** Away Mail: Please configure the script with a valid email address, smtp server, port number, username, and password");
				Irssi::print("*  Use these commands to configure:");
				Irssi::print("*  /set awaymail_to <email>");
				Irssi::print("*  /set awaymail_server <server>");
				Irssi::print("*  /set awaymail_port <port>");
				Irssi::print("*  /set awaymail_user <username>");
				Irssi::print("*  /set awaymail_pass <password>");
				Irssi::print("*  /set awaymail_alwaysnotify <YES|NO>");
				Irssi::print("*  /set awaymail_delaymins <minutes between emails>");
			}
		}
	}
}

sub filter_string {
	my $string	= shift;
	$string		=~ s/[^\w\s\.\!\@#\$\%^&\*\(\)\[\]\{\}\-\+=,<>:\?\/]//g; # only allow these characters
	return $string;
}

sub reset_time {
	$time	= 0;
}

sub valid_email {
	my $email	= shift;
	return $email =~ m/[\w\.\%+\-]+\@[\w\.\-]+\.[a-zA-Z]{2,4}/;
}

Irssi::settings_add_str('awaymail', 'awaymail_to', "");
Irssi::settings_add_str('awaymail', 'awaymail_from', "");
Irssi::settings_add_str('awaymail', 'awaymail_server', "");
Irssi::settings_add_str('awaymail', 'awaymail_port', "465");
Irssi::settings_add_str('awaymail', 'awaymail_user', "");
Irssi::settings_add_str('awaymail', 'awaymail_pass', "");
Irssi::settings_add_bool('awaymail', 'awaymail_alwaysnotify', 0);
Irssi::settings_add_str('awaymail', 'awaymail_delaymins', "10");
Irssi::signal_add_last('print text', 'handle_printtext');
Irssi::signal_add_last('message private', 'handle_privatemsg');
Irssi::signal_add_last('send command', 'reset_time');
Irssi::signal_add_last('away mode changed', 'reset_time');

Irssi::print("*****\n* $IRSSI{name} $VERSION loaded.");
Irssi::print("*  Use these commands to configure:");
Irssi::print("*  /set awaymail_to <email>");
Irssi::print("*  /set awaymail_server <server>");
Irssi::print("*  /set awaymail_port <port>");
Irssi::print("*  /set awaymail_user <username>");
Irssi::print("*  /set awaymail_pass <password>");
Irssi::print("*  /set awaymail_alwaysnotify <YES|NO>");
Irssi::print("*  /set awaymail_delaymins <minutes between emails>");
