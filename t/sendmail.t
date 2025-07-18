#!/usr/bin/env perl

use strict;
use warnings;

use Email::Sender::Transport::SMTP;
use Test::MockingBird;
use Test::Most;

BEGIN { use_ok('Log::Abstraction') }

my $config = {
	logger => {
		sendmail => {
			host => 'smtp.example.com',
			port => 25,
			to => 'alerts@example.com',
			from => 'logger@example.com',
			subject => 'Subject',
		}
	},
	level => 'info'
};

# Mock sendmail
my $called = 0;
Test::Mockingbird::mock('Email::Sender::Transport::SMTP', 'send_email', sub {
	my ($self, $email, $env) = @_;

	$called++;
	isa_ok($email, 'Email::Abstract', 'Email is correct object');
	like($email->as_string(), qr/Test message/, 'Message body looks correct');

	return 1;
});

# Instantiate and log
eval {
	my $log = Log::Abstraction->new($config);
	$log->info('Test message');
	1;
} or do {
	fail("Log::Abstraction threw error: $@");
};

Test::Mockingbird::unmock('Email::Sender::Transport::SMTP', 'send_email');

ok($called, 'sendmail was called');

done_testing();
