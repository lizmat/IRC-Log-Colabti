[![Actions Status](https://github.com/lizmat/IRC-Log-Colabti/workflows/test/badge.svg)](https://github.com/lizmat/IRC-Log-Colabti/actions)

NAME
====

IRC::Log::Colabti - interface to IRC logs from colabti.org

SYNOPSIS
========

```raku
use IRC::Log::Colabti;

my $log = IRC::Log::Colabti.new($filename.IO);

say "Logs from $log.date()";
.say for $log.entries.List;

my $log = IRC::Log::Colabti.new($text, $date);
```

DESCRIPTION
===========

IRC::Log::Colabti provides an interface to the IRC logs that are available from colabti.org (raw format). Please see [IRC::Log](IRC::Log) for more information.

ADDITIONAL METHODS
==================

merge
-----

```raku
my $merged = $log.merge($channel);    # merge with Colabti archive of same date

my $merged = $log.merge($slurped);    # merge with another log file of same date

my $merged = $log.merge($other-log);  # merge with log object

my $merged = $log.merge($path.IO);    # merge with log file by IO::Path
```

The `merge` instance method attempts to add entries from another log of the same date that are not present in the entries of the instance. This functionality is intended to fix "holes" in the logs caused by temporary outages of the various loggers.

It takes a single positional argument, which can either be:

  * the name of a channel: fetches content from Colabti's website

  * a string with the contents of a log file

  * another IRC::Log object

  * an IO::Path object of the log file to merge with

It either returns `Nil` if no missing entries were found, or a freshly created object of the same type as the invocant.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

