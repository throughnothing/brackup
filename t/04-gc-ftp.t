# -*-perl-*-
#
# Garbage collection test with ftp target - set $ENV{BRACKUP_TEST_FTP} to run
#

use strict;
use Test::More;

use Brackup::Test;
use FindBin qw($Bin);
use Brackup::Util qw(tempfile);

if ($ENV{BRACKUP_TEST_FTP}) {
  plan tests => 24;
} else {
  plan skip_all => "\$ENV{BRACKUP_TEST_FTP} not set";
}

############### Backup 1

my ($digdb_fh, $digdb_fn) = tempfile();
close($digdb_fh);
my $root_dir = "$Bin/data";
ok(-d $root_dir, "test data directory exists");
my ($backup_file, $backup, $target) = do_backup(
                            with_confsec => sub {
                                my $csec = shift;
                                $csec->add("path",          $root_dir);
                                $csec->add("chunk_size",    "2k");
                                $csec->add("digestdb_file", $digdb_fn);
                            },
                            with_targetsec => sub {
                                my $tsec = shift;
                                $tsec->add("type",          'Ftp');
                                $tsec->add("ftp_host",      $ENV{FTP_HOST} || 'localhost');
                                $tsec->add("ftp_user",      $ENV{FTP_USER} || 'anonymous');
                                $tsec->add("ftp_password",  $ENV{FTP_PASSWORD} || 'user@example.com');
                                $tsec->add("inventorydb_type", $ENV{BRACKUP_TEST_INVENTORYDB_TYPE} || 'SQLite');
                            },
                            );
is(scalar $target->backups, 1, 'target has 1 backup');
sleep 1;

############### Backup 2

$root_dir = "$Bin/data-2";
ok(-d $root_dir, "test data-2 directory exists");
($backup_file, $backup, $target) = do_backup(
                            with_confsec => sub {
                                my $csec = shift;
                                $csec->add("path",          $root_dir);
                                $csec->add("chunk_size",    "2k");
                                $csec->add("digestdb_file", $digdb_fn);
                            },
                            with_target => $target,
                          );
is(scalar $target->backups, 2, 'target has 2 backups');

############### Do a prune

my $pruned_count = eval { $target->prune( keep_backups => 1) };
is($pruned_count, 1, 'one backup deleted in prune');

############### Do garbage collection

my $removed_count = eval { $target->gc };
is($@, '', "first gc successful");
is($removed_count, 3, "3 chunks removed after prune");

############### Add orphan chunks

my $orphan_chunks_count = int(rand 10) + 1;
Brackup::Test::add_orphan_chunks($backup->{root}, $target, $orphan_chunks_count);

############### Do garbage collection

$removed_count = eval { $target->gc };
is($@, '', "second gc successful");
is($removed_count, $orphan_chunks_count, "all orphan chunks removed");

# vim:sw=4:et

