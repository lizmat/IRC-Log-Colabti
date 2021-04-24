[![Actions Status](https://github.com/lizmat/IRC-Log-Colabti/workflows/test/badge.svg)](https://github.com/lizmat/IRC-Log-Colabti/actions)

NAME
====

IRC::Log::Colabti - interface to IRC logs from colabti.org

SYNOPSIS
========

```raku
use IRC::Log::Colabti;

my $log = IRC::Log::Colabti.new($filename);

.say for $log.entries;
```

DESCRIPTION
===========

IRC::Log::Colabti provides an interface to the IRC logs that are available from colabti.org (raw format). 

METHODS
=======

new
---

```raku
my $log = IRC::Log::Colabti.new($filename);
```

The `new` class method takes a filename as parameter, and returns an instantiated object representing the messages in that log file.

It will note problems on STDERR if any line could not be interpreted.

entries
-------

```raku
.say for $log.entries;
```

The `entries` instance method returns an array with entries from the log. It contains instances of one of the following classes:

    IRC::Log::Colabti::Joined
    IRC::Log::Colabti::Left
    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Self-Reference

CLASSES
=======

All of the classes that are returned by the `entries` methods, have the following methods in common:

### gist

Create the string representation of the entry as it originally occurred in the log.

### hour

The hour (in UTC) the entry was added to the log.

### minute

The minute (in UTC) the entry was added to the log.

### ordinal

Zero-based ordinal number of this entry within the minute it occurred.

### nick

The nick of the user that originated the entry in the log.

### hhmm

The representation for hour and minute used in the log: "[hh:mm]" for this entry.

### target

Representation of an anchor in an HTML-file for deep linking to this entry.

IRC::Log::Colabti::Joined
-------------------------

No other methods are provided.

IRC::Log::Colabti::Left
-----------------------

No other methods are provided.

IRC::Log::Colabti::Message
--------------------------

### text

The text that the user entered that resulted in this log entry.

IRC::Log::Colabti::Nick-Change
------------------------------

### new-nick

The new nick of the user that resulted in this log entry.

IRC::Log::Colabti::Self-Reference
---------------------------------

The text that the user entered that resulted in this log entry.

AUTHOR
======

Elizabeth Mattijsen <liz@wenzperl.nl>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

