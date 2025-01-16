use IRC::Log:ver<0.0.25+>:auth<zef:lizmat>;

my sub default-normalizer($text) {
    $text.subst("\x7F", '^H', :global)
         .subst("\x17", '^W', :global)
         .subst(/ "\x03" \d? /,                             :global)
         .subst(/ <[\x00..\x1f] - [\x09..\x0a] - [\x0d]> /, :global)
         .subst(/ '[' [ \d ';' ]? \d ** 1..2 m /,           :global)
}

class IRC::Log::Colabti:ver<0.0.52>:auth<zef:lizmat> does IRC::Log {

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
                    $last-hour   = $hour;  # UNCOVERABLE
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
                        elsif $message eq 'left' {  # UNCOVERABLE
                            IRC::Log::Left.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick;
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('is now known as ') {  # UNCOVERABLE
                            IRC::Log::Nick-Change.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :new-nick($message.substr(16));
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('sets mode: ') {  # UNCOVERABLE
                            my @nick-names = $message.substr(10).words;
                            my $flags     := @nick-names.shift;
                            IRC::Log::Mode.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :$flags, :@nick-names;
                            ++$nr-control-entries;
                        }
                        elsif $message.starts-with('changes topic to: ') {  # UNCOVERABLE
                            self.last-topic-change = IRC::Log::Topic.new:
                              :log(self), :$hour, :$minute, :$ordinal,
                              :$nick, :text($message.substr(18));
                            ++$nr-control-entries;
                            ++$nr-conversation-entries;
                        }
                        elsif $message.starts-with('was kicked by ') {  # UNCOVERABLE
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
                $added := True;  # UNCOVERABLE
            }
        }

        $added
          ?? self.WHAT.new($final.List.map(*.gist).join("\n"), $!Date)
          !! Nil
    }
    multi method merge(
      IRC::Log::Colabti:D: Channel:D $channel,
      :&normalizer = &default-normalizer
    ) {
        my $proc := run
          'curl', '-k', "$colabti/$channel?date=$!date&raw=on",
          :out, :!err;
        self.merge: normalizer($proc.out.slurp)
    }
    multi method merge(IRC::Log::Colabti:D: Str:D $text) {
        self.merge(self.WHAT.new($text, $!Date))
    }
    multi method merge(IRC::Log::Colabti:D: IO::Path:D $path) {
        self.merge(self.WHAT.new($path.slurp(:enc("utf8-c8")), $!Date))
    }
}

sub EXPORT() { IRC::Log::Colabti.EXPORT }

# vim: expandtab shiftwidth=4
