# Copyright (c) 2011 Alan Hamlett <alan.hamlett@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

use strict;
use warnings;
use vars qw($VERSION %IRSSI);

use Irssi qw(
    settings_get_bool
    settings_get_str
    settings_set_bool
    settings_set_str
);
our $VERSION = '3.03';
our %IRSSI = (
    authors     => 'Alan Hamlett',
    contact     => 'alan.hamlett@gmail.com',
    url         => 'https://raw.github.com/alanhamlett/AwayMail-Irssi-Plugin/master/awaymail.pl',
    name        => 'Away Mail',
    description => 'Sends email notification(s) when someone types your name or sends you a private msg. Hint: use with screen_away.pl',
    license     => 'MIT License',
    changed     => 'Sun Jul 29 00:26:00 PDT 2012',
);

my $help = "
AWAYMAIL
 Sends email notification(s) when someone types your name or sends you a private msg. Hint: use with screen_away.pl.

Source Code:
 http://ahamlett.com/AwayMail-Irssi-Plugin

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
 Net::SMTP::TLS::ButMaintained ( if awayamail_tls ON )
 MIME::Base64
 Authen::SASL

Available settings:
 /set awaymail_to <string>              - Email address where notifications are sent. ( Ex: you\@gmail.com )
 /set awaymail_server <string>          - SMTP server address. Default is smtp.gmail.com.
 /set awaymail_port <number>            - SMTP server port number. Default is 465.
 /set awaymail_from <string>            - From e-mail address if different from awaymail_user. ( Ex: you\@gmail.com )
 /set awaymail_user <string>            - Username for the SMTP server. ( Ex: you\@gmail.com )
 /set awaymail_pass <string>            - Optional password for the SMTP user. ( Ex: your gmail password )
 /set awaymail_delay <number>           - Limits emails to one per <number> minutes. Default is 1 email per 10 minutes.
 /set awaymail_ssl <ON|OFF>             - Use SSL when connecting to the SMTP server. Default is OFF.
 /set awaymail_tls <ON|OFF>             - Use TLS when connecting to the SMTP server. Default is OFF.

Available commands:
 /awaymail_test_send                    - Sends a test email to check your awaymail settings.
";

# buffer of message to be emailed
my %buffer = ();

# timeout to check buffer
my $timeout;

# print string formats
Irssi::theme_register([
    'awaymail_loaded', '%R>>%n %_AwayMail:%_ Loaded $0 version $1' . "\n" . '%R>>%n %_AwayMail:%_ type /HELP AWAYMAIL for configuration information',
    'awaymail_sent', '%R>>%n %_AwayMail:%_ Sent awaymail',
    'awaymail_test_sent', '%R>>%n %_AwayMail:%_ Sent awaymail test email',
    'awaymail_error', '%R>>%n %_AwayMail:%_ Error: $0',
]);

sub check_required_modules {
    if ( settings_get_bool('awaymail_ssl') ) { # SSL is turned on so check for required modules
        unless ( eval "use Net::SMTP::SSL; 1" ) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Net::SMTP::SSL must be installed");
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
            return 0;
        }
        unless ( eval "use MIME::Base64; 1" ) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module MIME::Base64 must be installed");
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
            return 0;
        }
        unless ( eval "use Authen::SASL; 1" ) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Authen::SASL must be installed");
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_ssl OFF and re-load this script");
            return 0;
        }
    } elsif ( settings_get_bool('awaymail_tls') ) { # SSL is turned on so check for required modules
        unless ( eval "use Net::SMTP::TLS::ButMaintained; 1" ) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Net::SMTP::TLS::ButMaintained must be installed");
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN or /SET awaymail_tls OFF and re-load this script");
            return 0;
        }
    } else {
        unless ( eval "use Net::SMTP; 1" ) {
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Perl module Net::SMTP must be installed");
            Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', "Install it with CPAN and re-load this script");
            return 0;
        }
    }
    return 1;
}

sub handle_print_text {
    my ($dest, $text, $stripped) = @_;

    # return unless message level PUBLIC
    return unless $dest->{level} & MSGLEVEL_PUBLIC;

    # return if this text doesn't trigger channel activity
    return if $dest->{level} & MSGLEVEL_NO_ACT;

    # return unless we are away
    return unless $dest->{server}->{usermode_away};

    my $me = $dest->{server}->{nick};

    # make sure our nick is surrounded by non-nick characters aka. someone really said our nick
    my $found_me = 0;
    my $pos = 0;
    while ( length($stripped) > $pos and ($pos = index($stripped, $me, $pos)) and $pos >= 0 ) {

        # Check for nick wrapped in non-nick chars a-z, A-Z, 0-9, [, ], \, `, _, ^, {, |, }, -
        unless( substr($stripped, $pos-1, 1) =~ /[a-zA-Z0-9[\]\\`_^{}|-]/ or substr($stripped, $pos+length($me), 1) =~ m/[a-zA-Z0-9[\]\\`_^{}|-]/ ) {
            $found_me = 1;
            last;
        }
        $pos++;
    }

    # return unless we found our nick in the message
    return unless $found_me;

    $stripped =~ /<\s*([^>]+)\s*>/;
    my $nick = $1;
    my $serv = $dest->{server}->{address};
    my $chan = $dest->{target};

    # encode as utf8 if string is decoded utf8
    utf8::encode($stripped) if utf8::is_utf8($stripped);
    utf8::encode($nick) if utf8::is_utf8($nick);
    utf8::encode($serv) if utf8::is_utf8($serv);
    utf8::encode($chan) if utf8::is_utf8($chan);

    # filter newlines because they can interfere with SMTP
    my $footer = "";
    if ( $nick =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from user's nick. Only UTF-8 supported. )";
    }
    if ( $stripped =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from user's nick. Only UTF-8 supported. )";
    }
    if ( $serv =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from server name. Only UTF-8 supported. )";
    }
    if ( $chan =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from channel name. Only UTF-8 supported. )";
    }

    my $key = "$nick said your name in $serv $chan";
    my $val = $stripped . $footer;
    add_to_buffer($key, $val);

    return;
}

sub handle_message_private {
    my ($server, $msg, $nick, $address) = @_;

    # return unless we are away
    return unless $server->{usermode_away};

    my $serv = $server->{address};

    # encode as utf8 if string is decoded utf8
    utf8::encode($nick) if utf8::is_utf8($nick);
    utf8::encode($msg) if utf8::is_utf8($msg);
    utf8::encode($serv) if utf8::is_utf8($serv);

    # filter newlines because they can interfere with SMTP
    my $footer = "";
    if ( $nick =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from user's nick. Only UTF-8 supported. )";
    }
    if ( $msg =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from user's nick. Only UTF-8 supported. )";
    }
    if ( $serv =~ s/[\r\n]//g ) {
        $footer .= "\n( Newlines filtered from server name. Only UTF-8 supported. )";
    }

    my $key = "$nick sent you a pm in server $serv";
    my $val = $msg . $footer;
    add_to_buffer($key, $val);

    return;
}

sub add_to_buffer {
    my ($key, $val) = @_;

    # remove timeout
    Irssi::timeout_remove($timeout) if defined $timeout;

    # Add message to buffer and set timeout to send email after 30 seconds
    #   to see if we can combine multiple messages in one email
    #   unless our buffer is already too large so we don't run out of RAM.
    # Limits buffer to 100 keys and 1,000 messages per key, or 51.2MB (SI units not MiB).
    # 51.2MB = 512 chars (max in IRC spec) x 1,000 messages x 100 keys
    return unless exists $buffer{$key} or keys(%buffer) < 100; # check number of keys
    return unless !exists $buffer{$key} or @{$buffer{$key}} < 1000; # check number messages in this key
    $val =~ s/\n\n/\n/g;
    $buffer{$key} = () unless exists $buffer{$key};
    push(@{$buffer{$key}}, $val);
    $timeout = Irssi::timeout_add(30*1000, 'check_buffer', '');

    return;
}

sub check_buffer {
    my ($data, $server) = @_;

    Irssi::timeout_remove($timeout) if defined $timeout;
    return unless scalar %buffer;

    # check if we sent an email recently
    my $delay = settings_get_str('awaymail_delay');
    $delay =~ s/\D//g;
    $delay = 10 unless $delay > 0;
    my $last_sent = settings_get_str('awaymail_last_sent_time');
    if ( $last_sent + $delay * 60 > time ) {
        $timeout = Irssi::timeout_add(($last_sent-time+$delay*60)*1000, 'check_buffer', '');
        return;
    }

    # send email message
    my $subject = scalar(keys %buffer) == 1 ? 'Irssi -- ' . (keys %buffer)[0] : 'Irssi -- Multiple messages';
    my $body;
    foreach my $key (keys %buffer) {
        my @messages = @{ $buffer{$key} };
        $body .= "__________________________________________________\n$key\n\n" . join("\n", @messages) . "\n\n";
    }
    %buffer = ();
    send_email($subject, $body);

    return;
}

sub send_email {
    my ($subject, $body) = @_;
    my $to       = settings_get_str('awaymail_to');
    my $from     = settings_get_str('awaymail_from') or settings_get_str('awaymail_user');
    my $server   = settings_get_str('awaymail_server');
    my $port     = settings_get_str('awaymail_port');
    my $username = settings_get_str('awaymail_user');
    my $password = settings_get_str('awaymail_pass');

    unless ( $to and $server and $port =~ /^\d+$/ and $username ) {
        Irssi::print($help, MSGLEVEL_CLIENTCRAP);
        return;
    }

    eval {

        # connect to smtp server
        my $smtp;
        if ( settings_get_bool('awaymail_ssl') ) {
            $smtp = Net::SMTP::SSL->new($server, Port => $port, DEBUG => 1,) or Irssi::print($!, MSGLEVEL_CLIENTCRAP);
            defined ($smtp->auth($username, $password)) or die "Can't authenticate: $!";
        } elsif ( settings_get_bool('awaymail_tls') ) {
            $smtp = eval { return Net::SMTP::TLS::ButMaintained->new($server, Port => $port, User => $username, Password => $password); };
        } else {
            $smtp = Net::SMTP->new($server, Port => $port);
            $smtp->auth($username, $password) if $password;
        }
        if (not defined $smtp) {
            my $error = 'Could not connect to SMTP server';
            $error = IO::Socket::SSL::errstr() if settings_get_bool('awaymail_ssl') && IO::Socket::SSL::errstr();
            die $error;
        }

        # send email to smtp server
        $smtp->mail($from);
        $smtp->to($to);
        $smtp->data();
        $smtp->datasend("To: $to\r\nFrom: $from\r\nSubject: $subject\r\n\r\n$body\r\n");
        $smtp->dataend();
        $smtp->quit();

        die IO::Socket::SSL::errstr() if settings_get_bool('awaymail_ssl') && IO::Socket::SSL::errstr();
    };

    # catch any error exceptions
    if ($@) {
        Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_error', $@);
        return;
    }

    # email sent
    settings_set_str("awaymail_last_sent_time", time());
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_sent');

    return;
}

sub reset_time {
    %buffer = ();
    settings_set_str('awaymail_last_sent_time', "0");
    return;
}

# Register user settings
Irssi::settings_add_str('awaymail', 'awaymail_to', "");
Irssi::settings_add_str('awaymail', 'awaymail_server', "localhost");
Irssi::settings_add_str('awaymail', 'awaymail_port', "25");
Irssi::settings_add_str('awaymail', 'awaymail_from', "");
Irssi::settings_add_str('awaymail', 'awaymail_user', "");
Irssi::settings_add_str('awaymail', 'awaymail_pass', "");
Irssi::settings_add_str('awaymail', 'awaymail_delay', "10");
Irssi::settings_add_bool('awaymail', 'awaymail_ssl', 0);
Irssi::settings_add_bool('awaymail', 'awaymail_tls', 0);

# Register script settings
Irssi::settings_add_str('awaymail', 'awaymail_last_sent_time', "0");

return 1 unless check_required_modules();

# Register script commands
Irssi::command_bind('awaymail_test_send', sub {
    my ($argument_string, $server_obj, $window_item_obj) = @_;

    my $subject = 'AwayMail Irssi Test';
    my $body = 'This is a test of your awaymail configuration.';
    send_email($subject, $body);
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_test_sent');

}, 'AwayMail');

# Register signal handlers
Irssi::signal_add_last('print text', 'handle_print_text');
Irssi::signal_add_last('message private', 'handle_message_private');
Irssi::signal_add_last('away mode changed', 'reset_time');

# Overwrite the help command for awaymail
Irssi::command_bind('help', sub {
    if ( lc $_[0] eq 'awaymail' ) {
        Irssi::print($help, MSGLEVEL_CLIENTCRAP);
        Irssi::signal_stop;
    }
});

Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'awaymail_loaded', $IRSSI{name}, $VERSION);

