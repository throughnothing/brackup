package Brackup::Target::CloudFiles;

use strict;
use warnings;
use base 'Brackup::Target';
use Net::Rackspace::CloudFiles;
use Carp qw(croak);

# fields in object:
#   cf  -- Net::Rackspace::CloudFiles
#   username
#   apiKey
#   chunkContainer : $self->{username} . "-chunks";
#   backupContainer : $self->{username} . "-backups";
#

#{{{ new
sub new {
    my ($class, $confsec) = @_;
    my $self = $class->SUPER::new($confsec);
    
    $self->{username} = $confsec->value("cf_username")
        or die "No 'cf_username'";
    $self->{apiKey} = $confsec->value("cf_api_key")
        or die "No 'cf_api_key'";

	$self->_common_cf_init;

    return $self;
}
#}}}
#{{{ _common_cf_init
sub _common_cf_init {
    my $self = shift;
    $self->{chunkContainerName}  = $self->{username} . "-chunks";
    $self->{backupContainerName} = $self->{username} . "-backups";

    $self->{cf} = Connection->new(
		username => $self->{username}, apiKey => $self->{apiKey});

	#createContainer makes the object and returns it, or returns it
	#if it already exists
	$self->{chunkContainer} = 
		$self->{cf}->createContainer($self->{chunkContainerName})
		or die "Failed to get chunk container";
	$self->{backupContainer} =
		$self->{cf}->createContainer($self->{backupContainerName})
		or die "Failed to get backup container";

}
#}}}
#{{{ _prompt
sub _prompt {
    my ($q) = @_;
    my $ans = <STDIN>;
    $ans =~ s/^\s+//;
    $ans =~ s/\s+$//;
    return $ans;
}
#}}}
#{{{ new_from_backup_header
sub new_from_backup_header {
    my ($class, $header) = @_;

    my $username  = ($ENV{'CF_USERNAME'} || 
		_prompt("Your CloudFiles username: "))
        or die "Need your Cloud Files username.\n";

    my $apiKey = ($ENV{'CF_API_KEY'} || 
		_prompt("Your CloudFiles api key: "))
        or die "Need your CloudFiles api key.\n";

    my $self = bless {}, $class;
    $self->{username} = $username;
    $self->{apiKey} = $apiKey;
    $self->_common_cf_init;
    return $self;
}
#}}}
#{{{ has_chunk
sub has_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;   # "sha1:sdfsdf" format scalar

    my $res = $self->{chunkContainer}->getObject($dig);

    return 0 unless $res;

	#return 0 if $@ && $@ =~ /key not found/;

	#TODO: check for content type?
	#return 0 unless $res->{content_type} eq "x-danga/brackup-chunk";
    return 1;
}
#}}}
#{{{ load_chunk
sub load_chunk {
    my ($self, $dig) = @_;

    my $val = $self->{chunkContainer}->getObject($dig)
        or return 0;
    return \ $val->read;
}
#}}}
#{{{ store_chunk
sub store_chunk {
    my ($self, $chunk) = @_;
    my $dig = $chunk->backup_digest;
    my $blen = $chunk->backup_length;
    my $chunkref = $chunk->chunkref;

	my $object = $self->{chunkContainer}->createObject(
		$dig,$$chunkref,'x-danga/brackup-chunk');
	if ($object)
	{
		return 1;
	}

	return 0;
}
#}}}
#{{{ delete_chunk
sub delete_chunk {
    my ($self, $dig) = @_;

	return $self->{chunkContainer}->deleteObject($dig)
}
#}}}
#{{{ chunks
sub chunks {
    my $self = shift;
	return $self->{chunkContainer}->listObjects();
}
#}}}
#{{{ store_backup_meta
sub store_backup_meta {
    my ($self, $name, $file) = @_;

    my $rv = $self->{backupContainer}->createObject(
		$name,$file,'x-danga/brackup-meta',);

	return 1;
}
#}}}
#{{{ backups
sub backups {
    my $self = shift;

    my @ret;
	
	my @backups = $self->{backupContainer}->listObjects();
    foreach (@backups) {
		my $object = $self->{backupContainer}->getObject($_);
        push @ret, Brackup::TargetBackupStatInfo->new(
			$self, $_,
			time => $object->lastModified,
			size => $object->size);
    }
    return @ret;
}
#}}}
#{{{ get_backup
sub get_backup {
    my $self = shift;
    my ($name, $output_file) = @_;
	
	my $val = $self->{backupContainer}->getObject($name)
		or return 0; 

	$output_file ||= "$name.brackup";
    open(my $out, ">$output_file") or die "Failed to open $output_file: $!\n";

    my $outv = syswrite($out, $val->read);

    die "download/write error" unless 
		$outv == do { use bytes; length $val->read };
    close $out;

    return 1;
}
#}}}
#{{{ delete_backup
sub delete_backup {
    my $self = shift;
    my $name = shift;
    return $self->{backupContainer}->deleteObject($name);
}
#}}}
1;

=head1 NAME

Brackup::Target::CloudFiles - backup to Rackspace's CloudFiles Service

=head1 EXAMPLE

In your ~/.brackup.conf file:

  [TARGET:cloudfiles]
  type = CloudFiles
  cf_username  = ...
  cf_api_key =  ....

=head1 CONFIG OPTIONS

=over

=item B<type>

Must be "B<CloudFiles>".

=item B<cf_username>

Your Rackspace CloudFiles user name.

=item B<cf_api_key>

Your Rackspace CloudFiles api key.

=back

=head1 SEE ALSO

L<Brackup::Target>

L<Net::Rackspace::CloudFiles> -- required module to use Brackup::Target::CloudFiles

