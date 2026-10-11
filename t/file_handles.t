#!/usr/bin/env perl
# t/file_handles.t -- log files are kept open between messages: reopen(),
# reopen_interval, and noticing a file that has been renamed or deleted

use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::Most;

use Log::Abstraction;

my $tmpdir = tempdir(CLEANUP => 1);
my $count  = 0;

# A new, unused log-file path
sub new_path { return "$tmpdir/log" . ++$count . '.log' }

# Read a file's lines, tolerating CRLF line endings on Windows
sub lines {
	my ($path) = @_;
	open(my $fin, '<', $path) or return;
	my @lines = map { s/\r?\n\z//r } <$fin>;
	close $fin;
	return @lines;
}

# A logger writing just the message to $path
sub logger {
	my ($path, %args) = @_;
	return Log::Abstraction->new(level => 'info', file => $path, format => '%message%', %args);
}

# The handle the logger has open on $path, if any
sub handle { return $_[0]->{_handles}{$_[1]} && $_[0]->{_handles}{$_[1]}{fh} }

subtest 'the file is opened once, and each line is written at once' => sub {
	my $path = new_path();
	my $log = logger($path);
	$log->info('one');
	my $fh = handle($log, $path);
	ok($fh, 'the file is open');
	is_deeply([ lines($path) ], ['one'], 'the line is in the file before the next message');
	$log->info('two');
	is(handle($log, $path), $fh, 'the same handle is used for the next line');
	is_deeply([ lines($path) ], ['one', 'two'], 'both lines');
};

subtest 'every way of logging to a path' => sub {
	my ($p1, $p2, $p3) = (new_path(), new_path(), new_path());
	my $log = Log::Abstraction->new(level => 'info', format => '%message%',
		logger => { file => $p1, array => [] }, file => $p2);
	$log->info('x');
	ok(handle($log, $p1) && handle($log, $p2), 'logger hash file and top-level file');
	my $plain = Log::Abstraction->new($p3);
	$plain->warn('y');
	ok(handle($plain, $p3), 'logger path');
};

subtest 'reopen()' => sub {
	my $path = new_path();
	my $log = logger($path);
	$log->info('before');
	local ($@, $!) = ('error', 0);
	is($log->reopen(), $log, 'returns the logger');
	is($@, 'error', '$@ is unchanged');
	ok(!handle($log, $path), 'the file is closed');

	# As logrotate's postrotate SIGHUP would; on Windows an open file can't be renamed
	rename($path, "$path.1") or die "rename: $!";
	$log->info('after');
	is_deeply([ lines("$path.1") ], ['before'], 'the renamed file is untouched');
	is_deeply([ lines($path) ], ['after'], 'the next message opens a new file');
	lives_ok(sub { Log::Abstraction->new(logger => [])->reopen() }, 'nothing open');
};

subtest 'a renamed or deleted file is noticed' => sub {
	plan skip_all => "an open file can't be renamed or deleted on $^O" if($^O eq 'MSWin32');

	my $path = new_path();
	my $log = logger($path, reopen_interval => 0);
	$log->info('one');
	rename($path, "$path.old") or die "rename: $!";
	$log->info('two');
	is_deeply([ lines("$path.old") ], ['one'], 'renamed file');
	is_deeply([ lines($path) ], ['two'], 'new file');

	unlink($path) or die "unlink: $!";
	$log->info('three');
	is_deeply([ lines($path) ], ['three'], 'a deleted file is created again');
};

subtest 'a truncated file is appended to from the start' => sub {
	plan skip_all => "an open file can't be truncated on $^O" if($^O eq 'MSWin32');

	my $path = new_path();
	my $log = logger($path);
	$log->info('a long line before copytruncate');
	truncate($path, 0) or die "truncate: $!";
	$log->info('after');
	is_deeply([ lines($path) ], ['after'], 'no hole at the start of the file');
};

subtest 'reopen_interval' => sub {
	my $path = new_path();
	my $log = logger($path);
	$log->info('one');
	my $fh = handle($log, $path);
	$log->{_handles}{$path}{opened} -= 299;
	$log->info('two');
	is(handle($log, $path), $fh, 'kept open for less than 5 minutes');
	$log->{_handles}{$path}{opened} -= 1;
	$log->info('three');
	isnt(handle($log, $path), $fh, 'opened again after 5 minutes');

	$log = logger($path, reopen_interval => 10);
	$log->info('four');
	$fh = handle($log, $path);
	$log->{_handles}{$path}{opened} -= 10;
	$log->info('five');
	isnt(handle($log, $path), $fh, 'reopen_interval given');

	$log = logger($path, reopen_interval => 0);
	$log->info('six');
	$fh = handle($log, $path);
	$log->{_handles}{$path}{opened} -= 1_000_000;
	$log->info('seven');
	is(handle($log, $path), $fh, '0 turns it off');
	is_deeply([ lines($path) ], [qw(one two three four five six seven)], 'every line written once');

	for my $bad (-1, 'x', 1.5, '') {
		throws_ok(sub { Log::Abstraction->new(logger => [], reopen_interval => $bad) },
			qr/reopen_interval must be a non-negative integer/, "reopen_interval '$bad'");
	}
	throws_ok(sub { Log::Abstraction->new(logger => [])->new(reopen_interval => 'x') },
		qr/reopen_interval must be/, 'checked when cloning too');
};

subtest 'rotation closes the file first' => sub {
	my $path = new_path();
	my $log = logger($path, rotate_size => 1);
	$log->info('first');
	my $fh = handle($log, $path);
	$log->info('second');
	isnt(handle($log, $path), $fh, 'a new handle after rotating');
	is_deeply([ lines("$path.1") ], ['first'], 'rotated file');
	is_deeply([ lines($path) ], ['second'], 'new file');
};

subtest 'a failed write closes the file' => sub {
	my $path = new_path();
	my $log = logger($path);
	$log->info('one');
	close(handle($log, $path));
	{
		local $SIG{__WARN__} = sub { };    # print() on closed filehandle
		lives_ok(sub { $log->info('lost') }, 'does not die');
	}
	ok(!handle($log, $path), 'the handle is dropped');
	$log->info('two');
	is_deeply([ lines($path) ], ['one', 'two'], 'the next write opens the file again');
};

subtest 'clones open their own files' => sub {
	my $path = new_path();
	my $log = logger($path);
	$log->info('parent');
	{
		my $clone = $log->new(level => 'debug');
		$clone->info('clone');
		isnt(handle($clone, $path), handle($log, $path), 'not the same handle');
		$clone->reopen();
		ok(handle($log, $path), "the clone's reopen() leaves the parent's file open");
	}
	$log->info('parent again');
	is_deeply([ lines($path) ], ['parent', 'clone', 'parent again'], 'all lines written');
};

done_testing();
