use v6.*;

class IRC::Log::Colabti:ver<0.0.1>:auth<cpan:ELIZABETH> {
    has @.entries is built(False);

    role Entry {
        has Int $.hour;
        has Int $.minute;
        has Str $.nick;

        method hhmm() { sprintf '[%02d:%02d]', $!hour, $!minute }
    }

    class Message does Entry {
        has $.text;
        method gist() { "$.hhmm <$!nick> $!text" }
    }
    class Self-Reference does Entry {
        has $.text;
        method gist() { "$.hhmm * $!nick $!text" }
    }
    class Joined does Entry {
        method gist() { "$.hhmm *** $!nick joined" }
    }
    class Left does Entry {
        method gist() { "$.hhmm *** $!nick left" }
    }
    class Nick-Change does Entry {
        has $.new-nick;
        method gist() {
            "$.hhmm *** $!nick is now known as $!new-nick"
        }
    }

    method !INITIALIZE(Str:D $slurped) {

        for $slurped.lines.grep(*.chars) -> $line {
            sub ignored($reason) {
                note "Invalid line ignored because $reason\n$line";
            }

            if $line.starts-with('[') && $line.substr-eq('] ',6) {
                my $hour   := $line.substr(1,2).Int;
                my $minute := $line.substr(4,2).Int;
                my $text   := $line.substr(8);

                if $text.starts-with('<') {
                    with $text.index('> ') -> $index {
                        @!entries.push: Message.new:
                          :$hour, :$minute,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    else {
                        ignored("could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('* ') {
                    with $text.index(' ',2) -> $index {
                        @!entries.push: Self-Reference.new:
                          :$hour, :$minute,
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 1));
                    }
                    else {
                        ignored("self-reference nick");
                    }
                }
                elsif $text.starts-with('*** ') {
                    with $text.index(' ',4) -> $index {
                        my $nick    := $text.substr(4,$index - 4);
                        my $message := $text.substr($index + 1);
                        if $$message eq 'joined' {
                            @!entries.push: Joined.new: :$hour, :$minute, :$nick;
                        }
                        elsif $message eq 'left' {
                            @!entries.push: Left.new: :$hour, :$minute, :$nick;
                        }
                        elsif $message.starts-with('is now known as ') {
                            @!entries.push: Nick-Change.new:
                              :$hour, :$minute, :$nick,
                              :new-nick($message.substr(16));
                        }
                        else {
                            ignored('unclear control message');
                        }
                    }
                    else {
                        ignored("self-reference nick");
                    }
                }
            }
            else {
                ignored("no timestamp found");
            }
        }

        self
    }

    method new(IO() $file) {
        self.CREATE!INITIALIZE($file.slurp)
    }
}

=begin pod

=head1 NAME

IRC::Log::Colabti - interface to IRC logs from colabti.org

=head1 SYNOPSIS

=begin code :lang<raku>

use IRC::Log::Colabti;

my $log = IRC::Log::Colabti.new($filename);

.say for $log.entries;

=end code

=head1 DESCRIPTION

IRC::Log::Colabti provides an interface to the IRC logs that are available
from colabti.org (raw format).  

=head1 METHODS

=head2 new

=begin code :lang<raku>

my $log = IRC::Log::Colabti.new($filename);

=end code

The C<new> class method takes a filename as parameter, and returns
an instantiated object representing the messages in that log file.

It will note problems on STDERR if any line could not be interpreted.

=head2 entries

=begin code :lang<raku>

.say for $log.entries;

=end code

The C<entries> instance method returns an array with entries from the
log.  It contains instances of one of the following classes:

    IRC::Log::Colabti::Joined
    IRC::Log::Colabti::Left
    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Self-Reference

=head1 CLASSES

All of the classes that are returned by the C<entries> methods, have
the following methods in common:

=head3 gist

Create the string representation of the entry as it originally occurred
in the log.

=head3 hour

The hour (in UTC) the entry was added to the log.

=head3 minute

The minute the entry was added to the log.

=head3 nick

The nick of the user that originated the entry in the log.

=head2 IRC::Log::Colabti::Joined

No other methods are provided.

=head2 IRC::Log::Colabti::Left

No other methods are provided.

=head2 IRC::Log::Colabti::Message

=head3 text

The text that the user entered that resulted in this log entry.

=head2 IRC::Log::Colabti::Nick-Change

=head3 new-nick

The new nick of the user that resulted in this log entry.

=head2 IRC::Log::Colabti::Self-Reference

The text that the user entered that resulted in this log entry.

=head1 AUTHOR

Elizabeth Mattijsen <liz@wenzperl.nl>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
