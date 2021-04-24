use v6.*;

class IRC::Log::Colabti:ver<0.0.6>:auth<cpan:ELIZABETH> {
    has Date $.date;
    has @.entries  is built(False);
    has @.problems is built(False);

    role Entry {
        has     $.log     is required handles <entries date problems>;
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
        method pos() {
            self.entries.first({ $_ =:= self }, :k)
        }
    }

    class Joined does Entry {
        method gist() { "$.hhmm *** $!nick joined" }
    }
    class Left does Entry {
        method gist() { "$.hhmm *** $!nick left" }
    }
    class Message does Entry {
        has Str $.text is required;
        method gist() { "$.hhmm <$!nick> $!text" }
    }
    class Kick does Entry {
        has Str $.kickee;
        has Str $.spec;
        method gist() {
            "$.hhmm *** $!kickee was kicked by $!nick $!spec"
        }
    }
    class Mode does Entry {
        has Str $.flags;
        has Str @.nicks;
        method gist() {
            "$.hhmm *** $!nick sets mode: $!flags @.nicks.join(" ")"
        }
    }
    class Nick-Change does Entry {
        has Str $.new-nick is required;
        method gist() {
            "$.hhmm *** $!nick is now known as $!new-nick"
        }
    }
    class Self-Reference does Entry {
        has Str $.text is required;
        method gist() { "$.hhmm * $!nick $!text" }
    }
    class Topic does Entry {
        has Str $.text is required;
        method gist() { "$.hhmm *** $!nick changes topic to: $!text" }
    }

    method !accept(\type, |c --> Nil) {
        @!entries[@!entries.elems] := type.new(|c);
    }

    method !problem(Str:D $line, Str:D $reason --> Nil) {
        @!problems[@!problems.elems] := $reason => $line;
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
                        self!accept: Message,
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    else {
                        self!problem($line,"could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('* ') {
                    with $text.index(' ',2) -> $index {
                        self!accept: Self-Reference,
                          :log(self), :$hour, :$minute, :$ordinal,
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
                            self!accept: Joined,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message eq 'left' {
                            self!accept: Left,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message.starts-with('is now known as ') {
                            self!accept: Nick-Change,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :new-nick($message.substr(16));
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nicks  = $message.substr(10).words;
                            my $flags := @nicks.shift;
                            self!accept: Mode,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :$flags, :@nicks;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            self!accept: Topic,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :text($message.substr(18));
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            self!accept: Kick,
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :$kickee, :spec($message.substr($index + 1));
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
    IRC::Log::Colabti::Kick
    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Mode
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Self-Reference
    IRC::Log::Colabti::Topic

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

=head3 date

The C<Date> of this entry.

=head3 entries

The C<entries> of the C<log> of this entry.

=head3 gist

Create the string representation of the entry as it originally occurred
in the log.

=head3 hhmm

The representation for hour and minute used in the log: "[hh:mm]" for
this entry.

=head3 hour

The hour (in UTC) the entry was added to the log.

=head3 log

The C<IRC::Log::Colabti> object of which this entry is a part.

=head3 minute

The minute (in UTC) the entry was added to the log.

=head3 nick

The nick of the user that originated the entry in the log.

=head3 ordinal

Zero-based ordinal number of this entry within the minute it occurred.

=head3 pos

The position of this entry in the C<entries> of the C<log> of this entry.

=head3 problems

The C<problems> of the C<log> of this entry.

=head3 target

Representation of an anchor in an HTML-file for deep linking to this
entry.

=head2 IRC::Log::Colabti::Joined

No other methods are provided.

=head2 IRC::Log::Colabti::Left

No other methods are provided.

=head2 IRC::Log::Colabti::Kick

=head3 kickee

The nick of the user that was kicked in this log entry.

=head3 spec

The specification with which the user was kicked in this log entry.

=head2 IRC::Log::Colabti::Message

=head3 text

The text that the user entered that resulted in this log entry.

=head2 IRC::Log::Colabti::Mode

=head3 flags

The flags that the user entered that resulted in this log entry.

=head3 nicks

An array of nicknames (to which the flag setting should be applied)
that the user entered that resulted in this log entry.

=head2 IRC::Log::Colabti::Nick-Change

=head3 new-nick

The new nick of the user that resulted in this log entry.

=head2 IRC::Log::Colabti::Self-Reference

The text that the user entered that resulted in this log entry.

=head2 IRC::Log::Colabti::Topic

=head3 text

The new topic that the user entered that resulted in this log entry.

=head1 AUTHOR

Elizabeth Mattijsen <liz@wenzperl.nl>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
