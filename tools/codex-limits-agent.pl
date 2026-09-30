#!/usr/bin/perl
# Спрашивает у штатного `codex app-server` лимиты аккаунта и пишет их в ~/.codex/notch-limits-live.json,
# откуда их читает шторка. Запускать раз в несколько минут любым планировщиком по выбору пользователя.
# Модель не запускается, токены и ключи не читаются: вызываются только initialize,
# initialized и account/rateLimits/read.
use strict;
use warnings;
use IPC::Open3;
use IO::Select;
use JSON::PP;

my $home = $ENV{HOME} // (getpwuid($<))[7];
my $out  = "$home/.codex/notch-limits-live.json";
my @candidates = (
    $ENV{CODEX_BIN} // '',
    '/Applications/ChatGPT.app/Contents/Resources/codex',
    '/opt/homebrew/bin/codex',
    '/usr/local/bin/codex',
    "$home/.local/bin/codex",
    "$home/.codex/bin/codex",
);
my ($codex) = grep { length($_) && -x $_ } @candidates;
exit 0 unless $codex;

open(my $null, '>', '/dev/null') or exit 0;
my $pid = open3(my $in, my $outh, '>&' . fileno($null), $codex, 'app-server');
my $sel = IO::Select->new($outh);
my $json = JSON::PP->new->canonical;
my $buf = '';
my $deadline = time + 25;

sub send_msg { my ($h) = @_; print $in $json->encode($h) . "\n"; $in->flush; }
send_msg({ id => 1, method => 'initialize',
           params => { clientInfo => { name => 'boringNotch-limits-agent', version => '1.0' } } });

my ($initialized, $result) = (0, undef);
while (time < $deadline && !$result) {
    my @ready = $sel->can_read(1);
    next unless @ready;
    my $n = sysread($outh, my $chunk, 65536);
    last unless $n;
    $buf .= $chunk;
    while ($buf =~ s/^([^\n]*)\n//) {
        my $line = $1;
        next unless length $line;
        my $msg = eval { $json->decode($line) } or next;
        next unless ref $msg eq 'HASH' && defined $msg->{id};
        if ($msg->{id} == 1 && !$initialized) {
            $initialized = 1;
            send_msg({ method => 'initialized' });
            send_msg({ id => 2, method => 'account/rateLimits/read' });
        } elsif ($msg->{id} == 2) {
            $result = $msg;
            last;
        }
    }
}
close $in;
kill 'TERM', $pid;
waitpid($pid, 0);

exit 0 unless $result && ref $result->{result} eq 'HASH';
my $rl = $result->{result}{rateLimits};
exit 0 unless ref $rl eq 'HASH';

my %data = (updated => time);
for my $key (qw(primary secondary)) {
    my $w = $rl->{$key};
    next unless ref $w eq 'HASH' && defined $w->{usedPercent};
    $data{$key} = {
        used_percent   => $w->{usedPercent} + 0,
        window_minutes => defined $w->{windowDurationMins} ? $w->{windowDurationMins} + 0 : ($key eq 'primary' ? 300 : 10080),
        resets_at      => defined $w->{resetsAt} ? $w->{resetsAt} + 0 : undef,
    };
}
exit 0 unless $data{primary} || $data{secondary};

my $tmp = "$out.tmp.$$";
open(my $fh, '>', $tmp) or exit 0;
print $fh $json->encode(\%data);
close $fh;
rename $tmp, $out;
