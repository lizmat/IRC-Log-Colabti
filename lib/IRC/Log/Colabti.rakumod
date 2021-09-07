use v6.*;

use IRC::Log:ver<0.0.10>:auth<zef:lizmat>;

class IRC::Log::Colabti:ver<0.0.34>:auth<zef:lizmat> does IRC::Log {

    method parse(IRC::Log::Colabti:D:
      Str:D $slurped,
      Date:D $date
    ) is implementation-detail {
        $!date = $date;

        # assume spurious event without change that caused update
        return Empty if $!raw && $!raw eq $slurped;

        my $to-parse;
        my int $last-hour;
        my int $last-minute;
        my int $ordinal;
        my int $linenr;
        my int $pos;

        # done a parse before for this object
        if %!state -> %state {

            # adding new lines on log
            if $slurped.starts-with($!raw) {
                $last-hour   = %state<last-hour>;
                $last-minute = %state<last-minute>;
                $ordinal     = %state<ordinal>;
                $linenr      = %state<linenr>;
                $pos         = $!entries.elems;
                $to-parse   := $slurped.substr($!raw.chars);
            }

            # log appears to be altered, run it from scratch!
            else {
                $!entries.clear;
                %!nicks = @!problems = ();
                $!nr-control-entries = $!nr-conversation-entries = 0;
                $last-hour = $last-minute = $linenr = -1;
                $to-parse  = $slurped;
            }
        }

        # first parse
        else {
            $last-hour = $last-minute = $linenr = -1;
            $to-parse = $slurped;
        }

        # we need a "push" that does not containerize
        my int $initial-nr-entries = $!entries.elems;
        my int $accepted = $initial-nr-entries - 1;

        # accept an entry
        method !accept(\entry --> Nil) {
            with %!nicks{entry.nick} -> $entries-by-nick {
                $entries-by-nick.push($!entries.push(entry));
            }
            else {
                (%!nicks{entry.nick} := IterationBuffer.CREATE)
                  .push($!entries.push(entry));
            }
            ++$pos;
        }

        method !problem(Str:D $line, Str:D $reason --> Nil) {
            @!problems[@!problems.elems] := "Line $linenr: $reason" => $line;
        }

        for $to-parse.split("\n").grep({ ++$linenr; .chars }) -> $line {

            if $line.starts-with('[') && $line.substr-eq('] ',6) {
                my int $hour   = $line.substr(1,2).Int;
                my int $minute = $line.substr(4,2).Int;
                my $text      := $line.substr(8);

                if $minute == $last-minute && $hour == $last-hour {
                    ++$ordinal;
                }
                else {
                    $last-hour   = $hour;
                    $last-minute = $minute;
                    $ordinal     = 0;
                }

                if $text.starts-with('<') {
                    with $text.index('> ') -> $index {
                        self!accept: IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$!nr-conversation-entries;
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        self!accept: IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
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
                        self!accept: IRC::Log::Self-Reference.new:
                          :log(self), :$hour, :$minute, :$ordinal, :$pos,
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
                            self!accept: IRC::Log::Joined.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
                              :$nick;
                            ++$!nr-control-entries;
                        }
                        elsif $message eq 'left' {
                            self!accept: IRC::Log::Left.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
                              :$nick;
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('is now known as ') {
                            self!accept: IRC::Log::Nick-Change.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
                              :$nick, :new-nick($message.substr(16));
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nicks  = $message.substr(10).words;
                            my $flags := @nicks.shift;
                            self!accept: IRC::Log::Mode.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
                              :$nick, :$flags, :@nicks;
                            ++$!nr-control-entries;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            my $topic := IRC::Log::Topic.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
                              :$nick, :text($message.substr(18));
                            self!accept: $topic;
                            $!last-topic-change = $topic;
                            ++$!nr-conversation-entries;
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            self!accept: IRC::Log::Kick.new:
                              :log(self), :$hour, :$minute, :$ordinal, :$pos,
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
        $!raw   = $slurped;
        %!state = :parsed($slurped.chars),
          :$last-hour, :$last-minute, :$ordinal, :$linenr;

        $!entries.Seq.skip($initial-nr-entries)
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
from colabti.org (raw format).  Please see L<IRC::Log> for more information.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
