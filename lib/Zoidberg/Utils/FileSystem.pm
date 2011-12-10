package Zoidberg::Utils::FileSystem;

our $VERSION = '0.98';

use strict;
#use File::Spec;
use Env qw/@PATH/;
use File::Spec; # TODO make more use of this lib
use Encode;
use Exporter::Tidy 
	default => [qw/path list_path list_dir unique_file regex_glob/];

our $DEVNULL = File::Spec->devnull();

sub path {
	# return absolute path
	# argument: string optional: reference
	my $string = shift || return $ENV{PWD};
	my $refer = $_[0] ? path(shift @_) : $ENV{PWD}; # possibly recurs
	$refer =~ s/\/$//;
	$string =~ s{/+}{/}; # ever tried using $::main::main::main::something ?
	unless ($string =~ m{^/}) {
		if ( $string =~ /^~([^\/]*)/ ) {
			if ($1) {
				my @info = getpwnam($1); 
				# @info = ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell).
				$string =~ s{^~$1/?}{$info[7]/};
			}
			else { $string =~ s{^~/?}{$ENV{HOME}/}; }
		}
		elsif ( $string =~ s{^\.(\.+)(/|$)}{}) { 
			my $l = length($1);
			$refer =~ s{(/[^/]*){0,$l}$}{};
			$string = $refer.'/'.$string;
		}
		else {
			$string =~ s{^\.(/|$)}{};
			$string = $refer.'/'.$string;
		}
	}
	$string =~ s/\\//g;
	return $string;
}

sub list_dir {
	my $dir = @_ ? shift : $ENV{PWD};
	$dir =~ s#/$## unless $dir eq '/';
	$dir = path($dir);

	opendir DIR, $dir or die "could not open dir: $dir";
	my @items = grep {$_ !~ /^\.{1,2}$/} readdir DIR ;
	closedir DIR;

	@items = map Encode::decode_utf8($_, 1), @items;
	return @items;
}

sub list_path { return map list_dir($_), grep {-d $_} @PATH }

sub unique_file {
	my $string = pop || "untitledXXXX";
	my ($file, $number) = ($string, 0);
	$file =~ s/XXXX/$number/;
	while ( -e $file ) {
		if ($number > 256) {
			$file = undef;
			last;
		} # infinite loop protection
		else {
			$file = $string;
			$file =~ s/XXXX/$number/;
		}
		$number++
	};
	die qq/could not find any non-existent file for string "$string"/
		unless defined $file;
	return $file;
}

# [! => [^
# *  => .*
# ?  => .?
# leave [] {} ()
# quote other like $ @ % etc.

#sub glob {
#
#}

sub regex_glob {
	my ($glob, $opt) = @_;
	my @regex = $Zoidberg::CURRENT->{stringparser}->split(qr#/#, $glob);
	return _regex_glob_recurs(\@regex, '.', $opt);
}

sub _regex_glob_recurs {
	my ($regexps, $dir, $opt) = @_;
	my $regexp = shift @$regexps;
	$regexp = "(?$opt:".$regexp.')' if $opt;
	#debug "globbing for dir '$dir', regexp '$regexp', opt '$opt'\n";
	opendir DIR, $dir;
	my @matches = @$regexps
		? ( map  { _regex_glob_recurs([@$regexps], $dir.'/'.$_, $opt) }
		    grep { -d $_ and $_ !~ /^\.{1,2}$/ and m/$regexp/ } readdir DIR )
		: ( map "$dir/$_", grep { $_ !~ /^\.{1,2}$/ and m/$regexp/ } readdir DIR ) ;
	closedir DIR;
	return @matches;
}

1;

__END__

=pod

=head1 NAME

Zoidberg::Utils::FileSystem - Filesystem routines

=head1 DESCRIPTION

This module contains a few routines dealing with files and/or directories.
Mainly used to speed up searching $ENV{PATH} by "hashing" the filesystem.

Although when working within the Zoidberg framework this module should be used through
the L<Zoidberg::Utils> interface, it also can be used on it's own.

=head1 EXPORT

By default none, potentially all functions listed below.

=head1 FUNCTIONS

=over 4

=item C<path($file, $reference)>

Returns the absolute path for possible relative C<$file>
C<$reference> is optional an defaults to C<$ENV{PWD}>

=item C<list_dir($dir)>

Returns list of content of dir. Does a lookup for the absolute path name
and omits the '.' and '..' dirs.

=item C<list_path()>

Returns a list of all items found in directories listed in C<$ENV{PATH}>,
non existing directories in C<$ENV{PATH}> are silently ignored.

=back

=head1 TODO

More usage of File::Spec ?

=head1 AUTHOR

R.L. Zwart E<lt>rlzwart@cpan.orgE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>

=cut
