use IRC::Log:ver<0.0.24>:auth<zef:lizmat>;

class IRC::Log::Colabti:ver<0.0.50>:auth<zef:lizmat> does IRC::Log {

    method !problem(Str:D $line, Int:D $linenr, Str:D $reason --> Nil) {
        $!problems.push: "Line $linenr: $reason" => $line;
    }

    method parse-log(IRC::Log::Colabti:D:
      str $text,
          $last-hour               is raw,
          $last-minute             is raw,
          $ordinal                 is raw,
          $linenr                  is raw,
          $nr-control-entries      is raw,
          $nr-conversation-entries is raw,
    --> Nil) is implementation-detail {

        my str $last-line = "";
        for $text.split("\n").map({
            ++$linenr;
            if .chars && $_ ne $last-line {
                $last-line = $_;
            }
        }) -> $line {

            if $line.starts-with('[') && $line.substr-eq('] ',6) {
                my int $hour   = my str $ = $line.substr(1,2);  # fast Str to
                my int $minute = my str $ = $line.substr(4,2);  # int conversion
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
                        ++$nr-conversation-entries;
                    }
                    orwith $text.index('> ', :ignoremark) -> $index {
                        IRC::Log::Message.new:
                          :log(self), :$hour, :$minute, :$ordinal,
                          :nick($text.substr(1,$index - 1)),
                          :text($text.substr($index + 2));
                        ++$nr-conversation-entries;
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
                        ++$nr-conversation-entries;
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
                            ++$nr-control-entries;
                        }
                        elsif $message eq 'left' {
                            IRC::Log::Left.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick;
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('is now known as ') {
                            IRC::Log::Nick-Change.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :new-nick($message.substr(16));
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('sets mode: ') {
                            my @nick-names = $message.substr(10).words;
                            my $flags     := @nick-names.shift;
                            IRC::Log::Mode.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :$flags, :@nick-names;
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('changes topic to: ') {
                            self.last-topic-change = IRC::Log::Topic.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :text($message.substr(18));
                            ++$nr-control-entries;
                            ++$nr-conversation-entries;
                        }
                        elsif $message.starts-with('was kicked by ') {
                            my $kickee := $nick;
                            my $index  := $message.index(' ', 14);
                            $nick      := $message.substr(14, $index - 14);
                            IRC::Log::Kick.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :$kickee,
                              :spec($message.substr($index + 1));
                            ++$nr-control-entries;
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
    }

    my subset Channel of Str where / ^ <[-\w]>+ $ /;
    my constant $colabti = 'https://colabti.org/irclogger/irclogger_log';

    proto method merge(|) {*}
    multi method merge(IRC::Log::Colabti:D: IRC::Log:D $other) {
        my  @left[1440];  @left[.heartbeat].push: $_ for   self.entries.List;
        my @right[1440]; @right[.heartbeat].push: $_ for $other.entries.List;

        my $final := IterationBuffer.new;
        my $added := False;
        for ^1440 -> int $beat {
            with @left[$beat] -> @messages {
                with @right[$beat] -> @rmessages {
                    my int $insert-at = -1;
                    for @rmessages -> $message {
                        with @messages.first(* eqv $message, :k) {
                            $insert-at = $_;
                        }
                        else {
                            @messages.splice(++$insert-at, 0, $message);
                            $added := True;
                        }
                    }
                }
                $final.push: $_ for @messages;
            }
            orwith @right[$beat] -> @messages {
                $final.push: $_ for @messages;
                $added := True;
            }
        }

        $added
          ?? self.WHAT.new($final.List.map(*.gist).join("\n"), $!Date)
          !! Nil
    }
    multi method merge(IRC::Log::Colabti:D: Channel:D $channel) {
        my $proc := run
          'curl', '-k', "$colabti/$channel?date=$!date;raw=on",
          :out, :!err;
        self.merge($proc.out.slurp)
    }
    multi method merge(IRC::Log::Colabti:D: Str:D $text) {
        self.merge(self.WHAT.new($text, $!Date))
    }
    multi method merge(IRC::Log::Colabti:D: IO::Path:D $path) {
        self.merge(self.WHAT.new($path.slurp(:enc("utf8-c8")), $!Date))
    }
}

sub EXPORT() { IRC::Log::Colabti.EXPORT }

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

=head1 ADDITIONAL METHODS

=head2 merge

=begin code :lang<raku>

my $merged = $log.merge($channel);    # merge with Colabti archive of same date

my $merged = $log.merge($slurped);    # merge with another log file of same date

my $merged = $log.merge($other-log);  # merge with log object

my $merged = $log.merge($path.IO);    # merge with log file by IO::Path

=end code

The C<merge> instance method attempts to add entries from another log of
the same date that are not present in the entries of the instance.  This
functionality is intended to fix "holes" in the logs caused by temporary
outages of the various loggers.

It takes a single positional argument, which can either be:
=item the name of a channel: fetches content from Colabti's website
=item a string with the contents of a log file
=item another IRC::Log object
=item an IO::Path object of the log file to merge with

It either returns C<Nil> if no missing entries were found, or a freshly
created object of the same type as the invocant.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
