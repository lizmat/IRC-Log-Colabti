use v6.*;

class IRC::Log::Colabti:ver<0.0.9>:auth<cpan:ELIZABETH> {
    has Date $.date;
    has @.entries  is built(False);
    has @.problems is built(False);

    role Entry {
        has     $.log     is required handles <entries date problems>;
        has Int $.hour    is required;
        has Int $.minute  is required;
        has Int $.ordinal is required;
        has Str $.nick    is required;

        method seen-at() {
            '['
              ~ ($!hour < 10 ?? "0$!hour" !! $!hour)
              ~ ':'
              ~ ($!minute < 10 ?? "0$!minute" !! $!minute)
              ~ ']'
        }
        method hhmm() { 
            ($!hour < 10 ?? "0$!hour" !! $!hour)
              ~ ($!minute < 10 ?? "0$!minute" !! $!minute)
        }
        method target() {
            $!ordinal ?? "$.hhmm-$!ordinal" !! $.hhmm
        }
        method pos() {
            self.entries.first({ $_ =:= self }, :k)
        }
    }

    class Joined does Entry {
        method gist() { "$.seen-at *** $!nick joined" }
    }
    class Left does Entry {
        method gist() { "$.seen-at *** $!nick left" }
    }
    class Message does Entry {
        has Str $.text is required;
        method gist() { "$.seen-at <$!nick> $!text" }
    }
    class Kick does Entry {
        has Str $.kickee;
        has Str $.spec;
        method gist() {
            "$.seen-at *** $!kickee was kicked by $!nick $!spec"
        }
    }
    class Mode does Entry {
        has Str $.flags;
        has Str @.nicks;
        method gist() {
            "$.seen-at *** $!nick sets mode: $!flags @.nicks.join(" ")"
        }
    }
    class Nick-Change does Entry {
        has Str $.new-nick is required;
        method gist() {
            "$.seen-at *** $!nick is now known as $!new-nick"
        }
    }
    class Self-Reference does Entry {
        has Str $.text is required;
        method gist() { "$.seen-at * $!nick $!text" }
    }
    class Topic does Entry {
        has Str $.text is required;
        method gist() { "$.seen-at *** $!nick changes topic to: $!text" }
    }

    method !INITIALIZE(Str:D $slurped, Date:D $date) {
        $!date := $date;

        my $last-hour   := -1;
        my $last-minute := -1;
        my $ordinal;
        my int $linenr  = -1;

        method !accept(\object --> Nil) {
            @!entries[@!entries.elems] := object;
        }

        method !problem(Str:D $line, Str:D $reason --> Nil) {
            @!problems[@!problems.elems] := "Line $linenr: $reason" => $line;
        }

        for $slurped.split("\n").grep({ ++$linenr; .chars }) -> $line {

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
                        self!accept: Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        self!accept: Message.new:
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
                        self!accept: Self-Reference.new:
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
                            self!accept: Joined.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message eq 'left' {
                            self!accept: Left.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$nick;
                        }
                        elsif $message.starts-with('is now known as ') {
                            self!accept: Nick-Change.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :new-nick($message.substr(16));
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nicks  = $message.substr(10).words;
                            my $flags := @nicks.shift;
                            self!accept: Mode.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :$flags, :@nicks;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            self!accept: Topic.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$nick,
                              :text($message.substr(18));
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            self!accept: Kick.new:
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
            elsif $line.trim.chars {
                self!problem($line, "no timestamp found");
            }
        }

        self
    }

    method IO2Date(IO:D $path) {
        try $path.basename.split(".").head.Date
    }

    multi method new(
      IO:D $path,
      Date() $date = self.IO2Date($path)
    ) {
        self.CREATE!INITIALIZE($path.slurp(:enc("utf8-c8")), $date)
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

=head1 CLASS METHODS

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

=head2 IO2Date

=begin code :lang<raku>

with IRC::Log::Colabti.IO2Date($path) -> $date {
    say "the date of $path is $date";
}
else {
    say "$path does not appear to be a log file";
}

=end code

The C<IO2Date> class method interpretes the given C<IO::Path> object
and attempts to elide a C<Date> object from it.  It returns C<Nil> if
it could not.

=head1 INSTANCE METHODS

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
lines that could not be interpreted in the log.  The key is a string
with the line number and a reason it could not be interpreted.  The
value is the actual line.

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

A string representation of the hour and the minute of this entry ("hhmm").

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

=head3 seen-at

The representation for hour and minute used in the log: "[hh:mm]" for
this entry.

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
