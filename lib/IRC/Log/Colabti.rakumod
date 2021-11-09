use IRC::Log:ver<0.0.15>:auth<zef:lizmat>;

class IRC::Log::Colabti:ver<0.0.39>:auth<zef:lizmat> does IRC::Log {

    method !problem(Str:D $line, Int:D $linenr, Str:D $reason --> Nil) {
        $!problems.push: "Line $linenr: $reason" => $line;
    }

    method parse(IRC::Log::Colabti:D:
       Str:D $text,
      Date:D $date
    ) is implementation-detail {
        $!date = $date;

        # assume spurious event without change that caused update
        return Empty if $!raw && $!raw eq $text;

        my $to-parse;
        my int $last-hour;
        my int $last-minute;
        my int $ordinal;
        my int $linenr;

        # done a parse before for this object
        if %!state -> %state {

            # adding new lines on log
            if $text.starts-with($!raw) {
                $last-hour   = %state<last-hour>;
                $last-minute = %state<last-minute>;
                $ordinal     = %state<ordinal>;
                $linenr      = %state<linenr>;
                $to-parse   := $text.substr($!raw.chars);
            }

            # log appears to be altered, run it from scratch!
            else {
                self.clear;
                $last-hour = $last-minute = $linenr = -1;
                $to-parse  = $text;
            }
        }

        # first parse
        else {
            $last-hour = $last-minute = $linenr = -1;
            $to-parse = $text;
        }

        # we need a "push" that does not containerize
        my int $initial-nr-entries = $!entries.elems;
        my int $accepted = $initial-nr-entries - 1;

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
                        IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                    }
                    else {
                        self!problem($line, $linenr,
                          "could not find nick delimiter");
                    }
                }
                elsif $text.starts-with('* ') {
                    with $text.index(' ',2) -> $index {
                        IRC::Log::Self-Reference.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(2,$index - 2)),
                          :text($text.substr($index + 1));
                    }
                    else {
                        self!problem($line, $linenr,
                          "self-reference nick");
                    }
                }
                elsif $text.starts-with('*** ') {
                    with $text.index(' ',4) -> $index {
                        my $nick    := $text.substr(4,$index - 4);
                        my $message := $text.substr($index + 1);
                        if $$message eq 'joined' {
                            IRC::Log::Joined.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick;
                        }
                        elsif $message eq 'left' {
                            IRC::Log::Left.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick;
                        }
                        elsif $message.starts-with('is now known as ') {
                            IRC::Log::Nick-Change.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :new-nick($message.substr(16));
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nicks  = $message.substr(10).words;
                            my $flags := @nicks.shift;
                            IRC::Log::Mode.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :$flags, :@nicks;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            self.last-topic-change = IRC::Log::Topic.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :text($message.substr(18));
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            IRC::Log::Kick.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :$kickee,
                              :spec($message.substr($index + 1));
                        }
                        else {
                            self!problem($line, $linenr,
                              'unclear control message');
                        }
                    }
                    else {
                        self!problem($line, $linenr,
                          "self-reference nick");
                    }
                }
            }
            elsif $line.trim.chars {
                self!problem($line, $linenr,
                  "no timestamp found");
            }
        }

        # save current state in case of updates
        $!raw   = $text;
        %!state = :parsed($text.chars),
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
