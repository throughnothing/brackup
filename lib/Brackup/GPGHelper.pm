package Brackup::GPGHelper;
use strict;
use warnings;
use Carp qw(croak);
require Exporter;
use Brackup::Util qw(tempfile slurp valid_params);

use vars qw(@ISA @EXPORT_OK);
@ISA = ('Exporter');
@EXPORT_OK = qw(decrypt_meta_file_if_needed decrypt_chunk_if_needed);

#{{{ decrypt_meta_file_if_needed
sub decrypt_meta_file_if_needed {
    my $meta_filename = shift;

    my $meta = slurp($meta_filename);

    if ($meta =~ /[\x00-\x08]/) { # silly is-binary heuristic
        $meta_filename = _decrypt_file($meta_filename, no_batch => 1);
    }
	return $meta_filename;
}
#}}}
#{{{ decrypt_chunk_if_needed
sub decrypt_chunk_if_needed {
    my $dataref = shift;
	my $gpg_recipient = shift;

    if ($gpg_recipient) {
        $dataref = _decrypt_data($dataref);
    }
	return $dataref;
}
#}}}
#{{{ _decrypt_file
sub _decrypt_file {
    my $filename = shift;
    my %opts = valid_params(['no_batch'], @_);


    unless ($ENV{'GPG_AGENT_INFO'})
    {
        my $err = q{#
                        # WARNING: trying to restore encrypted files,
                        # but $ENV{'GPG_AGENT_INFO'} not present.
                        # Are you running gpg-agent?
                        #
                    };
        $err =~ s/^\s+//gm;
        warn $err;
    }

	my $_enc_temp_filename =  $filename;

    my @list = ("gpg", @Brackup::GPG_ARGS,
                "--use-agent",
                !$opts{no_batch} ? ("--batch") : (),
                "--trust-model=always",
                "--output",  $_enc_temp_filename,
                "--yes", "--quiet",
                "--decrypt", $filename);
    system(@list)
        and die "Failed to decrypt with gpg: $!\n";

    return $_enc_temp_filename;
}
#}}}
#{{{ _decrypt_data
sub _decrypt_data {
    my $dataref = shift;

    unless ($ENV{'GPG_AGENT_INFO'})
    {
        my $err = q{#
                        # WARNING: trying to restore encrypted files,
                        # but $ENV{'GPG_AGENT_INFO'} not present.
                        # Are you running gpg-agent?
                        #
                    };
        $err =~ s/^\s+//gm;
        warn $err;
    }

	my $enc_temp_data_filename = (tempfile())[1];
	_write_to_file($enc_temp_data_filename, $dataref);

    my @list = ("gpg", @Brackup::GPG_ARGS,
                "--use-agent",
                "--trust-model=always",
                "--yes", "--quiet",
                "--decrypt",$enc_temp_data_filename);

    my $decrypted_data = `@list`;
	my $gpg_reval = `echo $?`;
    return $dataref unless  $gpg_reval == 0;

    return \$decrypted_data;
}
#}}}
#{{{ _write_to_file
sub _write_to_file {
    my ($filename, $ref) = @_;
    open (my $fh, ">$filename") or die "Failed to open $filename for writing: $!\n";
    print $fh $$ref;
    close($fh) or die;
    die "Restored file is not of the correct size" unless -s $filename == length $$ref;
    return 1;
}
#}}}

1;

