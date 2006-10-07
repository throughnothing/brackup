package Brackup::Root;
use strict;
use warnings;
use Carp qw(croak);
use File::Find;
use Brackup::DigestDatabase;

sub new {
    my ($class, $conf) = @_;
    my $self = bless {}, $class;

    my $name = $conf->name;
    $name =~ s!^SOURCE:!! or die;

    $self->{name}       = $name;
    $self->{dir}        = $conf->path_value('path');
    $self->{gpg_path}   = $conf->value('gpg_path') || "/usr/bin/gpg";
    $self->{gpg_rcpt}   = $conf->value('gpg_recipient');
    $self->{chunk_size} = $conf->byte_value('chunk_size'),
    $self->{ignore}     = [];

    $self->{gpg_args}   = [];  # TODO: let user set this.  for now, not possible

    $self->{digdb_file} = $conf->value('digestdb_file') || "$self->{dir}/.brackup-digest.db";
    $self->{digdb}      = Brackup::DigestDatabase->new($self->{digdb_file});

    die "No backup-root name provided." unless $self->{name};
    die "Backup-root name must be only a-z, A-Z, 0-9, and _." unless $self->{name} =~ /^\w+/;

    return $self;
}

sub gpg_path {
    my $self = shift;
    return $self->{gpg_path};
}

sub gpg_args {
    my $self = shift;
    return @{ $self->{gpg_args} };
}

sub gpg_rcpt {
    my $self = shift;
    return $self->{gpg_rcpt};
}

sub digdb {
    my $self = shift;
    return $self->{digdb};
}

sub chunk_size {
    my $self = shift;
    return $self->{chunk_size} || (64 * 2**20);  # default to 64MB
}

sub publicname {
    # FIXME: let users define the public (obscured) name of their roots.  s/porn/media/, etc.
    # because their metafile key names (which contain the root) aren't encrypted.
    return $_[0]{name};
}

sub name {
    return $_[0]{name};
}

sub ignore {
    my ($self, $pattern) = @_;
    push @{ $self->{ignore} }, $pattern;
}

sub path {
    return $_[0]{dir};
}

sub foreach_file {
    my ($self, $cb) = @_;

    chdir $self->{dir} or die "Failed to chdir to $self->{dir}";

    # run the callback on the root directory, since it isn't
    # matched by logic below
    $cb->(Brackup::File->new(root => $self, path => "."));

    find({
        no_chdir => 1,
        preprocess => sub {
            my $dir = $File::Find::dir;
            my @good_dentries;
          DENTRY:
            foreach my $dentry (@_) {
                next if $dentry eq "." || $dentry eq "..";

                my $path = "$dir/$dentry";
                $path =~ s!^\./!!;

                # skip the digest database file.  not sure if this is smart or not.
                # for now it'd be kinda nice to have, but it's re-creatable from
                # the backup meta files later, so let's skip it.
                next if $path eq $self->{digdb_file};

                my (@stat) = stat($path);
                my $is_dir = -d _;

                foreach my $pattern (@{ $self->{ignore} }) {
                    next DENTRY if $path =~ /$pattern/;
                    next DENTRY if $is_dir && "$path/" =~ /$pattern/;
                }
                push @good_dentries, $dentry;

                # TODO: pass along the stat info
                my $file = Brackup::File->new(root => $self, path => $path);
                $cb->($file);
            }

            # to let it recurse into the good directories we didn't
            # already throw away:
            return @good_dentries;
        },

        # we don't use this phase, as it didn't let us discard
        # directories early (before walking into them), so all work is
        # moved into preprocess phase.
        wanted => sub { },
    }, ".");
}

sub as_string {
    my $self = shift;
    return $self->{name} . "($self->{dir})";
}

sub du_stats {
    my $self = shift;

    my $show_all = $ENV{BRACKUP_DU_ALL};
    my @dir_stack;
    my %dir_size;
    my $pop_dir = sub {
        my $dir = pop @dir_stack;
        printf("%-20d%s\n", $dir_size{$dir} || 0, $dir);
        delete $dir_size{$dir};
    };
    my $start_dir = sub {
        my $dir = shift;
        unless ($dir eq ".") {
            my @parts = (".", split(m!/!, $dir));
            while (@dir_stack >= @parts) {
                $pop_dir->();
            }
        }
        push @dir_stack, $dir;
    };
    $self->foreach_file(sub {
        my $file = shift;
        my $path = $file->path;
        if ($file->is_dir) {
            $start_dir->($path);
            return;
        }
        if ($file->is_file) {
            my $size = $file->size;
            my $kB   = int($size / 1024) + ($size % 1024 ? 1 : 0);
            printf("%-20d%s\n", $kB, $path) if $show_all;
            $dir_size{$_} += $kB foreach @dir_stack;
        }
    });

    $pop_dir->() while @dir_stack;


}

1;

