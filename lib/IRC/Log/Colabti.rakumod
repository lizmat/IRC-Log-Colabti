use v6.*;

class IRC::Log::Colabti:ver<0.0.25>:auth<cpan:ELIZABETH> {
    has Date $.date;
    has Str  $.raw;
    has      $.entries;
    has int  $.nr-control-entries;
    has int  $.nr-conversation-entries;
    has      @.problems;
    has      %.nicks;
    has      %!state;  # hash with final state of internal parsing

#-------------------------------------------------------------------------------
# Expected messsage types

    role Entry {
        has     $.log  is built(:bind);
        has int $!hmo  is built(:bind);
        has str $.nick is built(:bind);

        method target() {
            my int $hour    = $.hour;
            my int $minute  = $.minute;
            my int $ordinal = $.ordinal;

            my $target = self.date
              ~ 'Z'
              ~ ($hour < 10 ?? "0$hour" !! $hour)
              ~ ':'
              ~ ($minute < 10 ?? "0$minute" !! $minute);

            $target = $target ~ '-' ~ ($ordinal < 10
              ?? "000$ordinal"
              !! $ordinal < 100
                ?? "00$ordinal"
                !! $ordinal < 1000
                  ?? "0$ordinal"
                  !! $ordinal
            ) if $ordinal;
            $target
        }

        method hour()     { $!hmo div 600000       }
        method minute()   { $!hmo div 10000 mod 60 }
        method ordinal()  { $!hmo mod 10000        }
        method date()     { $!log.date     }
        method entries()  { $!log.entries  }
        method problems() { $!log.problems }

        method prefix(--> '*** ') { }
        method gist() {
            '[' ~ self.hh-mm ~ '] ' ~ self.prefix ~ self.message
        }

        method sender(--> '') { }
        method control(      --> True) { }
        method conversation(--> False) { }

        method hhmm() { 
            my int $hour   = $.hour;
            my int $minute = $.minute;
            ($hour < 10 ?? "0$hour" !! $hour)
              ~ ($minute < 10 ?? "0$minute" !! $minute)
        }
        method hh-mm() { 
            my int $hour   = $.hour;
            my int $minute = $.minute;
            ($hour < 10 ?? "0$hour" !! $hour)
              ~ ":"
              ~ ($minute < 10 ?? "0$minute" !! $minute)
        }
        method pos() {
            self.entries.List.first({ $_ =:= self }, :k)
        }
    }

    class Joined does Entry {
        method message() { "$!nick joined" }
    }
    class Left does Entry {
        method message() { "$!nick left" }
    }
    class Kick does Entry {
        has Str $.kickee is built(:bind);
        has Str $.spec   is built(:bind);

        method message() { "$!kickee was kicked by $!nick $!spec" }
    }
    class Message does Entry {
        has Str $.text is built(:bind);

        method sender() { $!nick }
        method message() { $!text }
        method prefix(--> '') { }
        method control(    --> False) { }
        method conversation(--> True) { }
    }
    class Mode does Entry {
        has Str $.flags is built(:bind);
        has Str @.nicks is built(:bind);

        method message() { "$!nick sets mode: $!flags @.nicks.join(" ")" }
    }
    class Nick-Change does Entry {
        has Str $.new-nick is built(:bind);

        method message() { "$!nick is now known as $!new-nick" }
    }
    class Self-Reference does Entry {
        has Str $.text is built(:bind);

        method prefix(--> '* ') { }
        method message() { "$!nick $!text" }
        method control(    --> False) { }
        method conversation(--> True) { }
    }
    class Topic does Entry {
        has Str $.text is built(:bind);

        method message() { "$!nick changes topic to: $!text" }
        method conversation(--> True) { }
    }

#-------------------------------------------------------------------------------
# Main log parser logic

    method !INIT() {
        $!entries := IterationBuffer.CREATE;
        self
    }

    method !PARSE(Str:D $slurped, Date:D $date) {
        $!raw  := $slurped;
        $!date := $date;

        my $to-parse;
        my $last-hour;
        my $last-minute;
        my Int $ordinal;
        my int $linenr;

        # done a parse before, so we're adding new lines
        if %!state -> %state {
            $last-hour   := %state<last-hour>;
            $last-minute := %state<last-minute>;
            $ordinal      = %state<ordinal>;
            $linenr       = %state<linenr>;
            $to-parse    := $slurped.substr(%state<parsed>);
        }

        # first parse
        else {
            $last-hour   := -1;
            $last-minute := -1;
            $linenr       = -1;
            $to-parse    := $slurped;
        }

        # we need a "push" that does not containerize
        my int $accepted = $!entries.elems - 1;
        method !accept(\object --> Nil) {
            with %!nicks{object.nick} -> $entries-by-nick {
                $entries-by-nick.push($!entries.push(object));
            }
            else {
                (%!nicks{object.nick} := IterationBuffer.CREATE)
                  .push($!entries.push(object));
            }
        }

        method !problem(Str:D $line, Str:D $reason --> Nil) {
            @!problems[@!problems.elems] := "Line $linenr: $reason" => $line;
        }

        for $to-parse.split("\n").grep({ ++$linenr; .chars }) -> $line {

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
                          :log(self),
                          :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        self!accept: Message.new:
                          :log(self),
                          :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    else {
                        self!problem($line,"could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('* ') {
                    with $text.index(' ',2) -> $index {
                        self!accept: Self-Reference.new:
                          :log(self),
                          :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 1));
                        ++$!nr-conversation-entries;
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
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick;
                            ++$!nr-control-entries;
                        }
                        elsif $message eq 'left' {
                            self!accept: Left.new:
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick;
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('is now known as ') {
                            self!accept: Nick-Change.new:
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick, :new-nick($message.substr(16));
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nicks  = $message.substr(10).words;
                            my $flags := @nicks.shift;
                            self!accept: Mode.new:
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick, :$flags, :@nicks;
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            self!accept: Topic.new:
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick, :text($message.substr(18));
                            ++$!nr-conversation-entries;
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            self!accept: Kick.new:
                              :log(self),
                              :hmo(($hour * 60 + $minute) * 10000 + $ordinal),
                              :$nick, :$kickee,
                              :spec($message.substr($index + 1));
                            ++$!nr-control-entries;
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

        # save current state in case of updates
        %!state = :parsed($slurped.chars),
          :$last-hour, :$last-minute, :$ordinal, :$linenr;

        self
    }

#-------------------------------------------------------------------------------
# Class methods

    method IO2Date(IO:D $path) {
        try $path.basename.split(".").head.Date
    }

    proto method new(|) {*}
    multi method new(IRC::Log::Colabti:U:
      IO:D $path,
      Date() $date = self.IO2Date($path)
    ) {
        self.CREATE!INIT!PARSE($path.slurp(:enc("utf8-c8")), $date)
    }

    multi method new(IRC::Log::Colabti:U:
      Str:D $slurped,
      Date() $date
    ) {
        self.CREATE!INIT!PARSE($slurped, $date)
    }

#-------------------------------------------------------------------------------
# Instance methods

    method first-target(IRC::Log::Colabti:D:) { $!entries[0].target   }
    method last-target( IRC::Log::Colabti:D:) { $!entries.Seq.tail.target }

    multi method update(IRC::Log::Colabti:D: IO:D $path) {
        self!PARSE($path.slurp(:enc("utf8-c8")), $!date)
    }

    multi method update(IRC::Log::Colabti:D: Str:D $slurped) {
        self!PARSE($slurped, $!date)
    }
}

#-------------------------------------------------------------------------------
# Documentation

=begin pod

=head1 NAME

IRC::Log::Colabti - interface to IRC logs from colabti.org

=head1 SYNOPSIS

=begin code :lang<raku>

use IRC::Log::Colabti;

my $log = IRC::Log::Colabti.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries.List;

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

.say for $log.entries.List;                      # all entries

.say for $log.entries.Seq.grep(*.conversation);  # only actual conversation

=end code

The C<entries> instance method returns an IterationBuffer with entries from
the log.  It contains instances of one of the following classes:

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

The C<date> instance method returns the C<Date> object for this log.

=head2 first-target

=begin code :lang<raku>

say $first-target;  # 2021-04-23

=end code

The C<first-target> instance method returns the C<target> of the first entry.

=head2 last-target

=begin code :lang<raku>

say $last-target;  # 2021-04-29

=end code

The C<last-target> instance method returns the C<target> of the last entry.

=head2 nicks

=begin code :lang<raku>

for $log.nicks.sort(*.key) -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}

=end code

The C<nicks> instance method returns a C<Map> with the nicks seen
for this log as keys, and an C<IterationBuffer> with entries that originated
by that nick.

=head2 nr-control-entries

=begin code :lang<raku>

say $log.nr-control-entries;

=end code

The C<nr-control-entries> instance method returns an integer representing
the number of control entries in this log.  It is calculated lazily

=head2 nr-conversation-entries

=begin code :lang<raku>

say $log.nr-conversation-entries;

=end code

The C<nr-conversation-entries> instance method returns an integer representing
the number of conversation entries in this log.

=head2 problems

=begin code :lang<raku>

.say for $log.problems;

=end code

The C<problems> instance method returns an array with C<Pair>s of
lines that could not be interpreted in the log.  The key is a string
with the line number and a reason it could not be interpreted.  The
value is the actual line.

=head2 raw

=begin code :lang<raku>

say "contains 'foo'" if $log.raw.contains('foo');

=end code

The C<raw> instance method returns the raw text version of the log.  It can
e.g. be used to do a quick check whether a string occurs in the raw text,
before checking C<entries> for a given string.

=head2 update

=begin code :lang<raku>

$log.update($filename.IO);  # add any entries added to file

$log.update($slurped);      # add any entries added to string

=end code

The C<update> instance method allows updating a log with any additional
entries.  This is primarily intended to allow for updating a log on the
current date, as logs of previous dates should probably be deemed immutable.

=head1 CLASSES

All of the classes that are returned by the C<entries> methods, have
the following methods in common:

=head3 control

Returns C<True> if this entry is a control message.  Else, it returns C<False>.

These entry types are considered control messages:

    IRC::Log::Colabti::Joined
    IRC::Log::Colabti::Left
    IRC::Log::Colabti::Kick
    IRC::Log::Colabti::Mode
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Topic

=head3 conversation

Returns C<True> if this entry is part of a conversation.  Else, it returns
C<False>.

These entry types are considered conversational messages:

    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Self-Reference
    IRC::Log::Colabti::Topic

=head3 date

The C<Date> of this entry.

=head3 entries

The C<entries> of the C<log> of this entry.

=head3 gist

Create the string representation of the entry as it originally occurred
in the log.

=head3 hhmm

A string representation of the hour and the minute of this entry ("hhmm").

=head3 hh-mm

A string representation of the hour and the minute of this entry ("hh:mm").

=head3 hour

The hour (in UTC) the entry was added to the log.

=head3 log

The C<IRC::Log::Colabti> object of which this entry is a part.

=head3 message

The text representation of the entry.

=head3 minute

The minute (in UTC) the entry was added to the log.

=head3 nick

The nick of the user that originated the entry in the log.

=head3 ordinal

Zero-based ordinal number of this entry within the minute it occurred.

=head3 pos

The position of this entry in the C<entries> of the C<log> of this entry.

=head3 prefix

The prefix used in creating the C<gist> of this entry.

=head3 problems

The C<problems> of the C<log> of this entry.

=head3 sender

A representation of the sender.  The same as C<nick> for the C<Message>
class, otherwise the empty string as then the nick is encoded in the
C<message>.

=head3 target

Representation of an anchor in an HTML-file for deep linking to this
entry.  Can also be used as a sort key across entries from multiple
dates.

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

=head3 text

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
