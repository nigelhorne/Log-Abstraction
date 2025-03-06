use strict;
use warnings;
use Test::Most;
use Log::YetAnother;
use File::Temp qw/tempfile/;
use Sys::Syslog qw(:standard :macros);

# Test logging to an in-memory array
my @log_array;
my $logger = Log::YetAnother->new(logger => \@log_array);

$logger->_debug('This is a debug message');
$logger->_info('This is an info message');
$logger->_notice('This is a notice message');
$logger->_trace('This is a trace message');

is_deeply(
    \@log_array,
    [
        { level => 'debug', message => 'This is a debug message' },
        { level => 'info', message => 'This is an info message' },
        { level => 'notice', message => 'This is a notice message' },
        { level => 'trace', message => 'This is a trace message' }
    ],
    'Logged messages to array'
);

# Test logging to a file
my ($fh, $filename) = tempfile();
$logger = Log::YetAnother->new(logger => $filename);

$logger->_debug('File debug message');
$logger->_info('File info message');

open my $log_fh, '<', $filename or die "Could not open log file: $!";
my @log_lines = <$log_fh>;
close $log_fh;

like($log_lines[0], qr/DEBUG: Log::YetAnother::Log::YetAnother/, 'Logged debug message to file');
like($log_lines[0], qr/File debug message/, 'Logged correct debug message to file');
like($log_lines[1], qr/INFO: Log::YetAnother::Log::YetAnother/, 'Logged info message to file');
like($log_lines[1], qr/File info message/, 'Logged correct info message to file');

# Test logging to a code reference
my @code_log;
$logger = Log::YetAnother->new(logger => sub { push @code_log, @_ });

$logger->_debug('Code debug message');
$logger->_info('Code info message');

is_deeply(
    \@code_log,
    [
        {
            class => 'Log::YetAnother',
            function => 'main::test_logger',  # Adjust function name if needed
            line => 64,  # Adjust line number if needed
            level => 'debug',
            message => ['Code debug message']
        },
        {
            class => 'Log::YetAnother',
            function => 'main::test_logger',  # Adjust function name if needed
            line => 65,  # Adjust line number if needed
            level => 'info',
            message => ['Code info message']
        }
    ],
    'Logged messages to code reference'
);

# Test logging to syslog
$logger = Log::YetAnother->new(syslog => { type => 'unix' });

$logger->_warn({ warning => 'Syslog warning message' });

# Note: Verifying syslog output requires checking the syslog file, not done here

done_testing();
