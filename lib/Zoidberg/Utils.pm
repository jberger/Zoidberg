
package Zoidberg::Utils;

our $VERSION = '0.97';

use strict;
use vars '$AUTOLOAD';
use Zoidberg::Utils::Error;
use Exporter::Tidy
	default => [qw/:output :error/],
	output	=> [qw/output message debug/],
	error	=> [qw/error bug todo complain/],
	fs	=> [qw/path list_dir/],
	other	=> [qw/
		setting read_data_file read_file merge_hash
		complain typed_output output_is_captured
		list_path unique_file regex_glob
		getopt help usage version path2hashref 
	/] ;

our $ERROR_CALLER = 1;

our %loadable = (
	fs      => ['Zoidberg::Utils::FileSystem', qw/path list_dir list_path unique_file regex_glob/ ],
	output	=> ['Zoidberg::Utils::Output',     qw/output message debug complain typed_output output_is_captured/ ],
	getopt	=> ['Zoidberg::Utils::GetOpt',     qw/getopt help usage version path2hashref/ ],
);

sub AUTOLOAD {
	$AUTOLOAD =~ s/.*:://;
	return if $AUTOLOAD eq 'DESTROY';

	my ($class, @subs);
	for my $key (keys %loadable) {
		next unless grep {$AUTOLOAD eq $_} @{$loadable{$key}};
		($class, @subs) = @{delete $loadable{$key}};
		eval "use $class \@subs";
		die if $@;
		last;
	}

	die "Could not load '$AUTOLOAD'" unless $class;
	no strict 'refs';
	goto &{$AUTOLOAD};
}

## Various methods ##

sub setting {
	# FIXME support for Fish argument and namespace
	my $key = shift;
	return undef unless exists $Zoidberg::CURRENT->{settings}{$key};
	my $ref = $Zoidberg::CURRENT->{settings}{$key};
	return (wantarray && ref($ref) eq 'ARRAY') ? (@$ref) : $ref;
}

sub read_data_file {
	my $file = shift;
	error 'read_data_file() is not intended for fully specified files, try read_file()'
		if $file =~ m!^/!;
	for my $dir (setting('data_dirs')) {
		for ("$dir/data/$file", map "$dir/data/$file.$_", qw/pl pd yaml/) {
			next unless -f $_;
			error "Can not read file: $_" unless -r $_;
			return read_file($_);
		}
	}
	error "Could not find 'data/$file' in (" .join(', ', setting('data_dirs')).')';
}

sub read_file {
	my $file = shift;
        error "no such file: $file\n" unless -f $file;

	my $ref;
	if ($file =~ /^\w+$/) { todo 'executable data file' }
	elsif ($file =~ /\.(pl)$/i) {
		eval q{package Main; $ref = do $file; die $@ if $@ };
       	}
	elsif ($file =~ /\.(pd)$/i) { $ref = pd_read($file) }
	elsif ($file =~ /\.(yaml)$/i) { 
       		eval 'require YAML' or error $@;
		$ref = YAML::LoadFile($file);
	}
	else { error qq/Unkown file type: "$file"\n/ }

	error "In file $file\: $@" if $@;
	error "File $file did not return a defined value" unless defined $ref;
	return $ref;
}

sub pd_read {
	my $FILE = shift;

	print STDERR "Deprecated config file: $FILE - should be a .pl instead of .pd\n";

	open FILE, '<', $FILE or return undef;
	my $CONTENT = join '', (<FILE>);
	close FILE;
	my $VAR1;
	eval $CONTENT;
	complain("Failed to eval the contents of $FILE ($@)") if $@;
	return $VAR1;
}

sub merge_hash {
    my $ref = {};
    local $ERROR_CALLER = 2;
    $ref = _merge($ref, $_) for @_;
    return $ref;
}

sub _merge { # Removed use of Storable::dclone - can throw nasty bugs
	my ($ref, $ding) = @_;
	while (my ($k, $v) = each %{$ding}) {
            if (defined $$ref{$k} and ref($v) eq 'HASH') {
	    	error 'incompatible types for key: '.$k.' in merging hashes'
			unless ref($$ref{$k}) eq 'HASH';
                $$ref{$k} = _merge($$ref{$k}, $v); #recurs
            }
            else { $ref->{$k} = $v; }
        }
	return $ref;
}

1;

__END__

=head1 NAME

Zoidberg::Utils - An interface to zoid's utility libs

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

This module bundles common routines used by the Zoidberg 
object classes, especially the error and output routines.

It is intended as a bundle or cluster of several packages
so it is easier to keep track of all utility methods.

=head1 EXPORT

By default the ':error' and ':output' tags are exported.

The following export tags are defined:

=over 4

=item :error

Gives you C<error>, C<bug>, C<todo>, C<complain>; the first 3 belong to
L<Zoidberg::Utils::Error>, the last to L<Zoidberg::Utils::Output>.

=item :output

Gives you C<output>, C<message> and  C<debug>, all of which belong to
L<Zoidberg::Utils::Output>.

=item :fs

Gives you C<path> and C<list_dir>, which belong to 
L<Zoidberg::Utils::FileSystem>.

=back

Also methods listen below can be requested for import.

=head1 METHODS

=over 4

=item C<read_data_file($basename)>

Searches in zoid's data dirs for a file with basename C<$basename> and returns
a hash reference with it's contents.

This method should be used by all plugins etc. to ensure portability.

FIXME more explanation

=item C<read_file($file)>

Returns a hash reference with the contents of C<$file>.
Currently only perl scripts are read and these should return (or end with)
a hash reference. Possibly other formats like yaml will be added later.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

The import function was adapted from L<Exporter::Tidy>
by Juerd Waalboer <juerd@cpan.org>, it was modified to add the
clustering feature.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils::Error>,
L<Zoidberg::Utils::Output>,
L<Zoidberg::Utils::FileSystem>,
L<Zoidberg::Utils::GetOpt>

=cut

