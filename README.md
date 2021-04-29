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

IRC::Log::Colabti provides an interface to the IRC logs that are available from colabti.org (raw format). 

CLASS METHODS
=============

new
---

```raku
my $log = IRC::Log::Colabti.new($filename.IO);

my $log = IRC::Log::Colabti.new($text, $date);
```

The `new` class method either takes an `IO` object as the first parameter, and a `Date` object as the optional second parameter (eliding the `Date` from the basename if not specified), and returns an instantiated object representing the entries in that log file.

Or it will take a `Str` as the first parameter for the text of the log, and a `Date` as the second parameter.

Any lines that can not be interpreted, are ignored: they are available with the `problems` method.

IO2Date
-------

```raku
with IRC::Log::Colabti.IO2Date($path) -> $date {
    say "the date of $path is $date";
}
else {
    say "$path does not appear to be a log file";
}
```

The `IO2Date` class method interpretes the given `IO::Path` object and attempts to elide a `Date` object from it. It returns `Nil` if it could not.

INSTANCE METHODS
================

entries
-------

```raku
.say for $log.entries.List;                      # all entries

.say for $log.entries.Seq.grep(*.conversation);  # only actual conversation
```

The `entries` instance method returns an IterationBuffer with entries from the log. It contains instances of one of the following classes:

    IRC::Log::Colabti::Joined
    IRC::Log::Colabti::Left
    IRC::Log::Colabti::Kick
    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Mode
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Self-Reference
    IRC::Log::Colabti::Topic

date
----

```raku
say $log.date;
```

The `date` instance method returns the `Date` object for this log.

first-target
------------

```raku
say $first-target;  # 2021-04-23
```

The `first-target` instance method returns the `target` of the first entry.

last-target
-----------

```raku
say $last-target;  # 2021-04-29
```

The `last-target` instance method returns the `target` of the last entry.

nicks
-----

```raku
for $log.nicks.sort(*.key) -> (:key($nick), :value($entries)) {
    say "$nick has $entries.elems() entries";
}
```

The `nicks` instance method returns a `Map` with the nicks seen for this log as keys, and an `IterationBuffer` with entries that originated by that nick.

problems
--------

```raku
.say for $log.problems;
```

The `problems` instance method returns an array with `Pair`s of lines that could not be interpreted in the log. The key is a string with the line number and a reason it could not be interpreted. The value is the actual line.

update
------

```raku
$log.update($filename.IO);  # add any entries added to file

$log.update($slurped);      # add any entries added to string
```

The `update` instance method allows updating a log with any additional entries. This is primarily intended to allow for updating a log on the current date, as logs of previous dates should probably be deemed immutable.

CLASSES
=======

All of the classes that are returned by the `entries` methods, have the following methods in common:

### control

Returns `True` if this entry is a control message. Else, it returns `False`.

These entry types are considered control messages:

    IRC::Log::Colabti::Joined
    IRC::Log::Colabti::Left
    IRC::Log::Colabti::Kick
    IRC::Log::Colabti::Mode
    IRC::Log::Colabti::Nick-Change
    IRC::Log::Colabti::Topic

### conversation

Returns `True` if this entry is part of a conversation. Else, it returns `False`.

These entry types are considered conversational messages:

    IRC::Log::Colabti::Message
    IRC::Log::Colabti::Self-Reference
    IRC::Log::Colabti::Topic

### date

The `Date` of this entry.

### entries

The `entries` of the `log` of this entry.

### gist

Create the string representation of the entry as it originally occurred in the log.

### hhmm

A string representation of the hour and the minute of this entry ("hhmm").

### hour

The hour (in UTC) the entry was added to the log.

### log

The `IRC::Log::Colabti` object of which this entry is a part.

### minute

The minute (in UTC) the entry was added to the log.

### nick

The nick of the user that originated the entry in the log.

### ordinal

Zero-based ordinal number of this entry within the minute it occurred.

### pos

The position of this entry in the `entries` of the `log` of this entry.

### problems

The `problems` of the `log` of this entry.

### seen-at

The representation for hour and minute used in the log: "[hh:mm]" for this entry.

### target

Representation of an anchor in an HTML-file for deep linking to this entry. Can also be used as a sort key across entries from multiple dates.

IRC::Log::Colabti::Joined
-------------------------

No other methods are provided.

IRC::Log::Colabti::Left
-----------------------

No other methods are provided.

IRC::Log::Colabti::Kick
-----------------------

### kickee

The nick of the user that was kicked in this log entry.

### spec

The specification with which the user was kicked in this log entry.

IRC::Log::Colabti::Message
--------------------------

### text

The text that the user entered that resulted in this log entry.

IRC::Log::Colabti::Mode
-----------------------

### flags

The flags that the user entered that resulted in this log entry.

### nicks

An array of nicknames (to which the flag setting should be applied) that the user entered that resulted in this log entry.

IRC::Log::Colabti::Nick-Change
------------------------------

### new-nick

The new nick of the user that resulted in this log entry.

IRC::Log::Colabti::Self-Reference
---------------------------------

### text

The text that the user entered that resulted in this log entry.

IRC::Log::Colabti::Topic
------------------------

### text

The new topic that the user entered that resulted in this log entry.

AUTHOR
======

Elizabeth Mattijsen <liz@wenzperl.nl>

Source can be located at: https://github.com/lizmat/IRC-Log-Colabti . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

