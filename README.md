# NAME

Log::Abstraction - Logging Abstraction Layer

# VERSION

0.30

# SYNOPSIS

    use Log::Abstraction;

    my $logger = Log::Abstraction->new(logger => 'logfile.log');

    $logger->debug('This is a debug message');
    $logger->info('This is an info message');
    $logger->notice('This is a notice message');
    $logger->trace('This is a trace message');
    $logger->warn({ warning => 'This is a warning message' });

# DESCRIPTION

The `Log::Abstraction` class provides a flexible logging layer on top of different types of loggers,
including code references, arrays, file paths, and objects.
It also supports logging to syslog if configured.

# METHODS

## new

    my $logger = Log::Abstraction->new(%args);

Creates a new `Log::Abstraction` object.

The argument can be a hash,
a reference to a hash or the `logger` value.
The following arguments can be provided:

- `carp_on_warn`

    If set to 1,
    and `logger` is not given,
    call `Carp:carp` on `warn()`.

    Causes `error()` to `carp` if `croak_on_error` is not given.

- `croak_on_error`

    If set to 1,
    and `logger` is not given,
    call `Carp:croak` on `error()`.

- `config_file`

    Points to a configuration file which contains the parameters to `new()`.
    The file can be in any common format,
    including `YAML`, `XML`, and `INI`.
    This allows the parameters to be set at run time.

    On a non-Windows system,
    the class can be configured using environment variables starting with `"Log::Abstraction::"`.
    For example:

        export Log::Abstraction::script_name=foo

    It doesn't work on Windows because of the case-insensitive nature of that system.

- `level`

    The minimum level at which to log something,
    the default is "warning".

- `logger`

    A logger can be one or more of:

    - a code reference

        The code will be called with a hashref containing:

        - class
        - file
        - line
        - level
        - message - an arrayref of messages
        - ctx - passed to `new()`, an argument that can help to give context to the caller

    - an object
    - a hash of options
    - sendmail - send higher priority messages to an email address

        To send an e-mail,
        you need ["require Email::Simple"](#require-email-simple), ["require Email::Sender::Simple"](#require-email-sender-simple) and [Email::Sender::Transport::SMTP](https://metacpan.org/pod/Email%3A%3ASender%3A%3ATransport%3A%3ASMTP).

        The `sendmail` hash also accepts a `min_interval` key (seconds).
        When set, at most one email is sent per `min_interval` seconds; any
        messages that arrive during the cooldown are still logged to other
        backends but do not trigger a new email.
        The send time is stored in `_last_email_sent` on the object, so each
        instance has its own cooldown window; cloned objects inherit the
        parent's last-send timestamp at the moment of cloning.

    - array - a reference to an array
    - fd - containing a file descriptor to log to
    - file - containing the filename

    Defaults to [Log::Log4perl](https://metacpan.org/pod/Log%3A%3ALog4perl).
    In that case,
    the argument 'verbose' to new() will raise the logging level.

- `format`

    The format of the message.
    Expands:

    - %callstack%
    - %level%
    - %class%
    - %message%
    - %timestamp%

        &#x3d;%item \* %env\_foo%

        Replaces with `$ENV{foo}`

- `syslog`

    A hash reference for syslog configuration.
    Only warnings and above will be sent to syslog.
    This restriction should be lifted in the future,
    since it's reasonable to send notices and above to the syslog.

- `script_name`

    The name of the script.
    It's needed when `syslog` is given,
    if none is passed, the value is guessed.

Clone existing objects with or without modifications:

    my $clone = $logger->new();

## \_sanitize\_email\_header

    my $clean_value = _sanitize_email_header($raw_value);

Internal routine to remove carriage return and line feed characters from an email header value to prevent header injection or formatting issues.

- Input

    Takes a single scalar value, typically a string representing an email header field.

- Behavior

    If the input is undefined, returns \`undef\`. Otherwise, removes all newline characters (\`\\n\`), carriage returns (\`\\r\`), and CRLF pairs from the string.

- Output

    Returns the sanitized string with CR/LF characters removed.

## level($self, $level)

Get/set the minimum level to log at.
Returns the current level, as an integer.

## is\_debug

Are we at a debug level that will emit debug messages?
For compatibility with [Log::Any](https://metacpan.org/pod/Log%3A%3AAny).

## messages

Return all the messages emitted so far

## debug

    $logger->debug(@messages);

Logs a debug message.

## info

    $logger->info(@messages);

Logs an info message.

## notice

    $logger->notice(@messages);

Logs a notice message.

## error

    $logger->error(@messages);

Logs an error message. This method also supports logging to syslog if configured.
If not logging mechanism is set,
falls back to `croak`.

## fatal

    $logger->fatal(@messages);

Synonym of error.

## trace

    $logger->trace(@messages);

Logs a trace message.

## warn

    $logger->warn(@messages);
    $logger->warn(\@messages);
    $logger->warn(warning => \@messages);

Logs a warning message. This method also supports logging to syslog if configured.
If not logging mechanism is set,
falls back to `Carp`.

## \_high\_priority

Helper to handle important messages.

# EXAMPLES

## CSV file logging for BI import

The code-reference backend gives you full control over the output format.
The example below writes every message at `trace` level and above as a
CSV row to a file,
producing output that can be loaded directly into a spreadsheet or BI tool
(Tableau, Power BI, Metabase, etc.).

Each row contains: `timestamp`, `level`, `class`, `file`, `line`, `message`.

    use Log::Abstraction;

    my $csv_file = 'app_events.csv';

    # Write the header row once (skip if the file already exists and has data).
    unless (-s $csv_file) {
        open my $fh, '>', $csv_file or die "Cannot open $csv_file: $!";
        print $fh qq{timestamp,level,class,file,line,message\n};
        close $fh;
    }

    # Helper: quote a single CSV field (escapes embedded double-quotes).
    my $csv_field = sub {
        my $v = defined $_[0] ? $_[0] : '';
        $v =~ s/"/""/g;
        return qq{"$v"};
    };

    my $logger = Log::Abstraction->new(
        level  => 'trace',        # capture everything from trace upwards
        logger => sub {
            my $args = $_[0];

            my $timestamp = POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
            my $message  = join(' ', @{ $args->{message} // [] });

            open my $fh, '>>', $csv_file or return;
            print $fh join(',',
                $csv_field->($timestamp),
                $csv_field->($args->{level}),
                $csv_field->($args->{class}),
                $csv_field->($args->{file}),
                $csv_field->($args->{line}),
                $csv_field->($message),
            ), "\n";
            close $fh;
        },
    );

    $logger->trace('application started');
    $logger->info('user logged in', { user => 'alice' });
    $logger->warn({ warning => 'disk usage above 80%' });

The resulting `app_events.csv` looks like:

    timestamp,level,class,file,line,message
    "2026-05-27T14:00:00Z","trace","Log::Abstraction","app.pl","42","application started"
    "2026-05-27T14:00:01Z","info","Log::Abstraction","app.pl","43","user logged in"
    "2026-05-27T14:00:02Z","warn","Log::Abstraction","Log/Abstraction.pm","820","disk usage above 80%"

Note: `class` is always `Log::Abstraction` (or the subclass name if you subclass the
module).  For `trace`, `debug`, `info`, and `notice` calls, `file` and `line`
resolve to the caller's source location.  For `warn` and `error` calls the
extra `_high_priority` stack frame shifts the resolution one level inward, so
`file` and `line` point into the module rather than the calling script.

For production use, consider replacing the manual `$csv_field` quoting with
[Text::CSV](https://metacpan.org/pod/Text%3A%3ACSV) for correct handling of embedded newlines and other edge cases.

If you also want real-time alerting on critical events, add the email logic
directly inside the code-ref callback - test `$args->{level}` and call
your mailer for `warn` / `error` messages while still writing the CSV row
for every message.

Alternatively, use the `sendmail` hash-ref backend on its own (without the
code-ref) and add a `level` key to restrict emails to warn-and-above:

    my $logger = Log::Abstraction->new(
        level  => 'warn',
        logger => {
            sendmail => {
                host         => 'smtp.example.com',
                to           => 'ops@example.com',
                from         => 'logger@example.com',
                subject      => 'Application alert',
                level        => 'warn',   # only email at warn level and above
                min_interval => 300,      # at most one alert email per 5 minutes
            },
        },
    );

Note: the `sendmail` backend writes the module's standard text format, not
CSV.  To produce CSV rows _and_ send email alerts from the same logger,
embed both the CSV-write and the mail-send logic inside a single code-ref
callback as described above.

# AUTHOR

Nigel Horne `njh@nigelhorne.com`

# SEE ALSO

- [Test Dashboard](https://nigelhorne.github.io/Log-Abstraction/coverage/)

# SUPPORT

This module is provided as-is without any warranty.

Please report any bugs or feature requests to `bug-log-abstraction at rt.cpan.org`,
or through the web interface at
[http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Log-Abstraction](http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Log-Abstraction).
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

You can find documentation for this module with the perldoc command.

    perldoc Log::Abstraction

You can also look for information at:

- MetaCPAN

    [https://metacpan.org/dist/Log-Abstraction](https://metacpan.org/dist/Log-Abstraction)

- RT: CPAN's request tracker

    [https://rt.cpan.org/NoAuth/Bugs.html?Dist=Log-Abstraction](https://rt.cpan.org/NoAuth/Bugs.html?Dist=Log-Abstraction)

- CPAN Testers' Matrix

    [http://matrix.cpantesters.org/?dist=Log-Abstraction](http://matrix.cpantesters.org/?dist=Log-Abstraction)

- CPAN Testers Dependencies

    [http://deps.cpantesters.org/?module=Log::Abstraction](http://deps.cpantesters.org/?module=Log::Abstraction)

# COPYRIGHT AND LICENSE

Copyright (C) 2025-2026 Nigel Horne

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.
