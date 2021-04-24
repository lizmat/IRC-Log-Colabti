use v6.*;

class IRC::Log::Colabti:ver<0.0.3>:auth<cpan:ELIZABETH> {
    has Date $.date;
    has @.entries  is built(False);
    has @.problems is built(False);

    role Entry {
        has Int $.hour    is required;
        has Int $.minute  is required;
        has Int $.ordinal is required;
        has Str $.nick    is required;

        method hhmm() { sprintf '[%02d:%02d]', $!hour, $!minute }
        method target() {
            $!ordinal
              ?? sprintf('%02d%02d-%d', $!hour, $!minute, $!ordinal)
              !! sprintf('%02d%02d'   , $!hour, $!minute)
        }
    }

    class Message does Entry {
        has $.text is required;
        method gist() { "$.hhmm <$!nick> $!text" }
    }
    class Self-Reference does Entry {
        has $.text is required;
        method gist() { "$.hhmm * $!nick $!text" }
    }
    class Joined does Entry {
        method gist() { "$.hhmm *** $!nick joined" }
    }
    class Left does Entry {
        method gist() { "$.hhmm *** $!nick left" }
    }
    class Nick-Change does Entry {
        has $.new-nick is required;
        method gist() {
            "$.hhmm *** $!nick is now known as $!new-nick"
        }
    }

    method !problem(Str:D $line, Str:D $reason -->Nil) {
        @!problems.push($reason => $line);
    }

    method !INITIALIZE(Str:D $slurped, Date:D $date) {
        $!date := $date;

        my $last-hour   := -1;
        my $last-minute := -1;
        my $ordinal;

        for $slurped.lines.grep(*.chars) -> $line {

            if $line.starts-with('[') && $line.substr-eq('] ',6) {
                my $hour   := $line.substr(1,2).Int;
                my $minute := $line.substr(4,2).Int;
                my $text   := $line.substr(8);

                if $minute == $last-minute && $hour == $last-hour {
                    ++$ordinal;
                }
                else {
                    $last-hour   := $hour;
                    $last-minute := $minute;
                    $ordinal = 0;
                }

                if $text.starts-with('<') {
                    with $text.index('> ') -> $index {
                        @!entries.push: Message.new:
                          :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    else {
                        self!problem($line,"could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('* ') {
                    with $text.index(' ',2) -> $index {
                        @!entries.push: Self-Reference.new:
                          :$hour, :$minute, :$ordinal,
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 1));
                    }
                    else {
                        self!problem($line, "self-reference nick");
                    }
                }
                elsif $text.starts-with('*** ') {
                    with $text.index(' ',4) -> $index {
                        my $nick    := $text.substr(4,$index - 4);
                        my $message := $text.substr($index + 1);
                        if $$message eq 'joined' {
                            @!entries.push: Joined.new:
                              :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message eq 'left' {
                            @!entries.push: Left.new:
                              :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message.starts-with('is now known as ') {
                            @!entries.push: Nick-Change.new:
                              :$hour, :$minute, :$ordinal, :$nick,
                              :new-nick($message.substr(16));
                        }
                        else {
                            self!problem($line, 'unclear control message');
                        }
                    }
                    else {
                        self!problem($line, "self-reference nick");
                    }
                }
            }
            else {
                self!problem($line, "no timestamp found");
            }
        }

        self
    }

    multi method new(
      IO:D $file,
      Date() $date = $file.basename.split(".").head
    ) {
        self.CREATE!INITIALIZE($file.slurp, $date)
    }

    multi method new(Str:D $slurped, Date() $date) {
        self.CREATE!INITIALIZE($slurped, $date)
    }
}

=begin pod

=head1 NAME

IRC::Log::Colabti - interface to IRC logs from colabti.org

=head1 SYNOPSIS

=begin code :lang<raku>

use IRC::Log::Colabti;

my $log = IRC::Log::Colabti.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries;

my $log = IRC::Log::Colabti.new($text, $date);

=end code

=head1 DESCRIPTION

IRC::Log::Colabti provides an interface to the IRC logs that are available
from colabti.org (raw format).  

=head1 METHODS

=head2 new

=begin code :lang<raku>

my $log = IRC::Log::Colabti.new($filename.IO);

my $log = IRC::Log::Colabti.new($text, $date);

=end code

The C<new> class method either takes an C<IO> object as the first parameter,
and a C<Date> object as the optional second parameter (eliding the C<Date>
from the basename if not specified), and returns an instantiated object
representing the entries in that log file.

Or it will take a C<Str> as the first parameter for the text of the log,
and a C<Date> as the second parameter.

Any lines that can not be interpreted, are ignored: they are available
with the C<problems> method.

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

=head2 date

=begin code :lang<raku>

say $log.date;

=end code

It C<date> instance method returns the C<Date> object for this log.

=head2 problems

=begin code :lang<raku>

.say for $log.problems;

=end code

The C<problems> instance method returns an array with C<Pair>s of
lines that could not be interpreted in the log.  The key is a text
of the reason it could not be interpreted, and the value is the
actual line.

=head1 CLASSES

All of the classes that are returned by the C<entries> methods, have
the following methods in common:

=head3 gist

Create the string representation of the entry as it originally occurred
in the log.

=head3 hour

The hour (in UTC) the entry was added to the log.

=head3 minute

The minute (in UTC) the entry was added to the log.

=head3 ordinal

Zero-based ordinal number of this entry within the minute it occurred.

=head3 nick

The nick of the user that originated the entry in the log.

=head3 hhmm

The representation for hour and minute used in the log: "[hh:mm]" for
this entry.

=head3 target

Representation of an anchor in an HTML-file for deep linking to this
entry.

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
