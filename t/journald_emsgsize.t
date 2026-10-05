#!/usr/bin/env perl
# t/journald_emsgsize.t -- a journald datagram too big for the system's
# socket send buffer is retried with a shorter message.
#
# A CPAN smoker failed t/regressions.t because its send buffer was smaller
# than 200,000 bytes, so send() failed with EMSGSIZE ("Message too long"):
# https://matrix.perl-magpie.org/results/3720262e-c005-11f1-a083-8730a1ea2842
# This file fakes a small buffer by overriding send() before the module is
# compiled, so it holds on any system.

use strict;
use warnings;

use POSIX ();

# Datagrams bigger than this fail as they would with a small send buffer
our $FAKE_LIMIT = 50_000;
our @attempts;

BEGIN {
	*CORE::GLOBAL::send = sub (*$$;$) {
		my ($fh, $msg, $flags, $to) = @_;
		push @attempts, length($msg);
		if(length($msg) > $FAKE_LIMIT) {
			$! = POSIX::EMSGSIZE();
			return;
		}
		return defined($to) ? CORE::send($fh, $msg, $flags, $to) : CORE::send($fh, $msg, $flags);
	};
}

use Test::Most;
use Socket qw(AF_UNIX SOCK_DGRAM sockaddr_un MSG_DONTWAIT);
use File::Temp qw(tempdir);

{
	my $ok = eval { socket(my $probe, AF_UNIX, SOCK_DGRAM, 0) or die "$!\n"; close $probe; 1 };
	if(!$ok) {
		chomp(my $reason = $@);
		plan skip_all => "Unix domain sockets not available: $reason";
	}
}

use Log::Abstraction;

my $tmpdir = tempdir(CLEANUP => 1);
my $sockpath = "$tmpdir/small.socket";

sub send_message {
	my $message = shift;

	socket(my $recv, AF_UNIX, SOCK_DGRAM, 0) or die "socket: $!";
	bind($recv, sockaddr_un($sockpath)) or die "bind: $!";

	my @carps;
	local $SIG{__WARN__} = sub { push @carps, $_[0] };
	@attempts = ();
	Log::Abstraction->new(logger => { journald => { socket => $sockpath } }, level => 'debug')->info($message);

	my $data = '';
	recv($recv, $data, 1_000_000, MSG_DONTWAIT);
	close $recv;
	unlink $sockpath;
	return ($data, \@carps);
}

subtest 'EMSGSIZE is retried with a shorter message' => sub {
	my ($data, $carps) = send_message('x' x 300_000);

	is(scalar(@{$carps}), 0, 'no carp') or diag(@{$carps});
	cmp_ok(scalar(@attempts), '>', 1, 'the send was retried');
	cmp_ok(length($data), '<=', $FAKE_LIMIT, 'datagram fits the send buffer');
	like($data, qr/x \[truncated\]\nPRIORITY=/, 'message ends with the truncation marker');
};

subtest 'a small message is sent once, untouched' => sub {
	my ($data, $carps) = send_message('hello');

	is(scalar(@{$carps}), 0, 'no carp');
	is(scalar(@attempts), 1, 'one send');
	like($data, qr/^MESSAGE=hello$/m, 'message intact');
	unlike($data, qr/\[truncated\]/, 'not truncated');
};

subtest 'gives up, with one carp, when nothing fits' => sub {
	local $FAKE_LIMIT = 10;
	my ($data, $carps) = send_message('x' x 300_000);

	is($data, '', 'nothing delivered');
	is(scalar(grep { /journald send failed/ } @{$carps}), 1, 'one carp');
	cmp_ok($attempts[-1], '<', 5_000, 'retried down to the minimum');
};

done_testing();
