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

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

