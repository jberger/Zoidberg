package Zoidberg::Utils::GetOpt;

our $VERSION = '0.981';

use strict;
use Zoidberg::Utils::Error qw/error bug/;
use Zoidberg::Utils::Output qw/output debug/;
use Exporter::Tidy
	default => ['getopt'],
	other   => [qw/help usage version path2hashref/] ;

our $ERROR_CALLER = 1;

sub getopt { # hic sunt leones
	my ($conf, @args) = @_;
	my (%conf, @opts, %opts, $args);
	if (ref $conf) { 
		%conf = %$conf;
		goto PARSE_OPTS;
	}

	# parse config
	$conf{_args} = $1 if $conf =~ s/(?<!\S)([\@\%\*])\s*$//;
	goto PARSE_ARGS unless $conf and $args[0] =~ /^[+-]/;
	for (split /\s+/, $conf) {
		my $arg = s/([\$\@\%])$// ? $1 : 0;
		my ($opt, @al) = split ',', $_;
		unless ($opt =~ s/\*$//) {
			$conf{$opt} = $arg;
			$conf{_alias}{$_} = $opt for @al;
		}
		else {
			error 'config syntax error' if @al || ! length $_;
			$conf{$opt} = $arg;
			$conf{_glob} ||= [];
			push @{$conf{_glob}}, $opt;
		}
	}
	$conf{_glob} = '^('.join('|', map {s/^\+/\\+/; $_} @{$conf{_glob}}).')(?!-)' if $conf{_glob};
	#use Data::Dumper; print STDERR 'conf: ', Dumper \%conf;

	PARSE_OPTS:
	for ( # set default options
		[qw/h help/,    \&help   ],
		[qw/u usage/,   \&usage  ],
		[qw/v version/, \&version]
	) {
		next if exists $conf{$$_[1]};
		$conf{$$_[1]} = $$_[2];
		$conf{_alias}{'-'.$$_[0]} = $$_[1]
			unless exists $conf{_alias}{'-'.$$_[0]} or exists $conf{_alias}{$$_[0]};
	}

	my $delim = 0;
	while (@args) { # parse opts
		last unless $args[0] =~ /^(-|\+.)/;
		$_ = shift @args;
		/^(--|-|\+)(.*)/;
		++$delim and last unless length $2;
		my ($pre, $opt, $arg) = ($1, split '=', $2, 2);

		my (@chars, $type);
		my $raw = $pre.$opt;
		if (exists $conf{_alias}{$raw} or exists $conf{$raw}) { $opt = $raw }
		elsif (exists $conf{_glob} and $raw =~ /$conf{_glob}/) {
			$opt = $raw;
			$type = $conf{$1};
		}
		elsif ($pre ne '--' and length $opt > 1) { # try short options
			@chars = split '', $opt;
		}

		PARSE_OPT:
		$opt = shift @chars if @chars;
		$opt = $conf{_alias}{$opt} if exists $conf{_alias}{$opt};
	
		unless (defined $type) { # type is set if glob
			if (exists $conf{$opt}) { $type = $conf{$opt} }
			else { error "unrecognized option '$opt'" }
		}

		push @opts, $opt;
		if (! $type) { # no arg
			error "option '$opt' doesn't take an argument" if defined $arg;
			$opts{$opt} = ($pre eq '+') ? 0 : 1;
		}
		elsif (ref $type) { # CODE ... for default opts
			output $type->( (caller(1))[3], (caller)[0] ); # subroutine, package
			error {silent => 1, exit_status => 0}, 'getopt needed to pop stack';
		}
		else {
			$arg = defined($arg) ? $arg : shift(@args);
			error "option '$opt' requires an argument" unless defined $arg;
			if    ($type eq '$') { $opts{$opt} = $arg }
			elsif ($type eq '@') {
				if (ref $arg) {
					error 'argument is not a ARRAY reference'
						if ref($arg) ne 'ARRAY';
					if ($opts{$opt}) { push @{$opts{$opt}}, @$arg }
					else { $opts{$opt} = $arg }
				}
				else {
					$opts{$opt} ||= [];
					push @{$opts{$opt}}, $arg;
				}
			}
		}
		$arg = $type = undef;
		goto PARSE_OPT if @chars;
	};
	error @opts 
		? "option '$opts[-1]' doesn't take an argument" 
		: 'options found after first argument'          if !$delim and grep /^-/, @args;
	$opts{_opts} = \@opts if @opts; # keep %opts empty unless there are opts

	PARSE_ARGS: # parse args
	unless ($conf{_args}) { $args = [@args] }
	elsif  ($conf{_args} eq '@') {
		error "argument should be a ARRAY reference"
			if grep {ref($_) and ref($_) ne 'ARRAY'} @args;
		if (ref $args[0] and @args == 1) { $args = $args[0] }
		else { $args = [ map {ref($_) ? @$_ : $_} @args] }
	}
	elsif  ($conf{_args} eq '%') {
		error "argument should be a HASH reference"
			if grep {ref($_) and ref($_) ne 'HASH'} @args;
		if (ref $args[0] and @args == 1) { $args = $args[0] }
		else {
			my $error;
			$args = { map {
				if (ref $_) { (%$_) }
				else {
					m/(.*?)=(.*)/ or $error++; 
					($1 => $2)
				}
	       		} @args };
			error 'syntax error, should be \'key=value\'' if $error;
		}
	}
	elsif ($conf{_args} eq '*') {
		my (@keys, %vals);
		for (@args) {
			if (ref $_) {
				my $t = ref $_;
				if ($t eq 'ARRAY') { push @keys, @$_ }
				elsif ($t eq 'HASH') {
					push @keys, keys %$_;
					%vals = (%vals, %$_);
				}
				else { error "can't handle $t reference argument" }
			}
			elsif (m/(.*?)=(.*)/) {
				push @keys, $1;
				$vals{$1} = $2;
			}
			else { push @keys, $_ }
		}
		return \%opts, \@keys, \%vals;
	}

	return \%opts, $args; 
}

sub usage {
	$_[2] = 1;
	goto &help;
}

sub help {
	my ($cmd, $file, $usage) = @_;

	$cmd ||= (caller(1))[3];
	$file = $1 if $cmd =~ s/(.*):://;
	$file =~ s/::/\//g;
	$file =~ s/\.pm$//;
	($file) = grep {-e $_} map {("$_/$file.pod", "$_/$file.pm")} @INC
		unless $file =~ m#^/#;

	open POD, $file || error "Could not read $file";
	my ($help, $p, $o) = ('', 0, 0);
	while (<POD>) {
		if ($p) {
			if    (/^=over/)  { $o++ }
			elsif (/^=back/)  { $o-- }
			elsif (/^=(item(?!\s+$cmd)|back|cut)/) {
				last unless $o;
			}
			$help .= $_ unless $usage and ! $o and ! /^=item\s+$cmd/;
			# only return 'item' lines if short format
		}
		elsif (/^=item\s+$cmd/) {
			$p = 1;
			$help = $_;
		}
	}
	close POD;

	$help =~ s/^\s+|\s+$//g;
	if ($usage) {
		$help =~ s/^=item\s+/  /gm;
		$help = "usage:\n".$help;
	}
	else { $help =~ s/^=\w+\s+/= /gm }
	$help =~ s/(\w)<<(.*?)>>|\w<(.*?)>/
		($1 eq 'B') ? "\"$2$3\"" :
		($1 eq 'C') ? "`$2$3`"   : "'$2$3'"
	/ge;
	return $help;
}

sub version {
	my (undef, $class) = @_;
	no strict 'refs';
	return ${$class.'::LONG_VERSION'} || $class.' '.${$class.'::VERSION'};
}

sub path2hashref {
	my ($hash, $key) = @_;
	my $path = '/';
	while ($key =~ s#^/*(.+?)/##) {
		$path .= $1 . '/';
		if (! defined $$hash{$1}) { $$hash{$1} = {} }
		elsif (ref($$hash{$1}) ne 'HASH') { return undef, undef, $path } # bail out
		$hash = $$hash{$1};
	}
	return $hash, $key, $path;
}

1;

__END__

=head1 NAME

Zoidberg::Utils::GetOpt - Yet another GetOpt module

=head1 SYNOPSIS

	use Zoidberg::Utils qw/getopt/;
	
	sub export {
		my (undef, $args) = getopt '%', @_;
		for (keys %$args) { $ENV{$_} = $$args{$_} }
	}
	
	export( 'PS1=\\u\\h\\$ ' );
	export( {PS1 => '\\u\\h\\$ '} ); # equivalent with the above
	
	sub kill {
		my ($opts, $args) = getopt 'list,l s$ n$ @', @_;
		die 'to many arguments' if @$args > 1;
		goto &list_sigs if $$opts{list};
		my $sig = $$opts{s} || $$opts{n} || '15';
		for my $pid (@$args) {
		    ...
		}
	}
	
	kill( '-n', 'TERM', '--', @pids );
	kill( '-n' => 'TERM', \@pids ); # equivalent with the above
	
=head1 DESCRIPTION

Although when working within the Zoidberg framework this module should be used
through the L<Zoidberg::Utils> interface, it also can be used on it's own.

This module provides a general 'getopt' interface, aimed at built-in functions
for zoid. The idea is that this library can handle both commandline arguments
and perl data structures. Also it should be flexible enough to parse most
common styles for commandline arguments.

=head1 EXPORT

The function C<getopt()> is exported by default whe nusing the module directly.
Also you can ask for C<usage()> and C<version()> to be exported.

=head1 METHODS

=over 4

=item C<getopt($config)>

Returns references to data structures with options and arguments.

Otions are seperated by whitespace in the config string.
A single letter in the config string represents a bit-wise option, a word
is regarded as a (gnu-style) long option. You can have long and short versions
of the same option by writing them seperated by a ','. When a option 
(or a combination of option and aliases) is followed by a sigil ('$' or '@')
argument(s) of that type are read. Note that the array sigil ('@') does not mean
that an option takes multiple arguments at once, but that the option can occur
multiple times, it also means that the option can take an array reference as argument.
For short options a '+' variant is used for the non-true value.

If an options config string starts with an '-' or an '+' it is considered a long
option with a single '-' (not gnu but X-style) or '+'.

If the config string ends in a single sigil ('%' or '@') a reference of this type
is returned containing all the arguments following the options.
If the config string end in a single '*' two references are returned, an array reference
containing all arguments, and a hash reference containing values for those arguments that
formed key-value pairs.
If no sigil is given a array reference is returned containing all remaining arguments 
exactly as they were found.

The options '--version' (alias '-V') and '--usage' (alias '-u', '--help'
and '-h') are by default special. TODO how are these returned / printed ?

Options can B<not> start with an '_', it is reserved for some meta fields.

FIXME tell about globs and _opts

=item C<version()>

Returns a version string for the calling module. Used for the default
'--version' option.

=item C<usage($cmd)>

Returns a usage message for C<$cmd> based on the POD of the calling
module. Used for the default '--usage' and '--help' options.

=item C<path2hashref(\%hash, $path)>

Returns a reference to a sub-hash of %hash, followed by a key
and the path to that sub-hash. Intended to be used by built-in
commands that manipulate hash structures for handling commandline args.

=back

=head1 AUTHOR

Jaap Karssenberg (Pardus) E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>

=cut
