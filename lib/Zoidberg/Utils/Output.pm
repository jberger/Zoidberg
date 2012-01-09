
package Zoidberg::Utils::Output;

our $VERSION = '0.981';

use strict;
use Data::Dumper;
use POSIX qw/floor ceil/;
use Exporter::Tidy
	default => [qw/output message debug complain/],
	other   => [qw/typed_output output_is_captured/];

our %colours = ( # Copied from Term::ANSIScreen
	'clear'      => 0,    'reset'      => 0,
	'bold'       => 1,    'dark'       => 2,
	'underline'  => 4,    'underscore' => 4,
	'blink'      => 5,    'reverse'    => 7,
	'concealed'  => 8,

	'black'      => 30,   'on_black'   => 40,
	'red'        => 31,   'on_red'     => 41,
	'green'      => 32,   'on_green'   => 42,
	'yellow'     => 33,   'on_yellow'  => 43,
	'blue'       => 34,   'on_blue'    => 44,
	'magenta'    => 35,   'on_magenta' => 45,
	'cyan'       => 36,   'on_cyan'    => 46,
	'white'      => 37,   'on_white'   => 47,
);

sub output_is_captured {
	return $Zoidberg::CURRENT->{_builtin_output} ? 1 : 0;
}

sub output {
	if ($Zoidberg::CURRENT->{_builtin_output}) { # capturing output from builtin
		push @{ $Zoidberg::CURRENT->{_builtin_output} }, @_;
		return 1;
	}
	else { typed_output('output', @_) }
}

sub message {
	return 1 if ! $Zoidberg::CURRENT->{settings}{interactive};
	typed_output('message', @_);
}

sub debug {
	my $class = caller;
	no strict 'refs';
	#local $Data::Dumper::Maxdepth = 2;
	return 1 unless $Zoidberg::CURRENT->{settings}{debug} || ${$class.'::DEBUG'};
	my $fh = select STDERR;
	my @caller = caller;
	typed_output('debug', "$caller[0]: $caller[2]: ", @_);
	select $fh;
	1;
}

sub complain { # strip @INC: for little less verbose output
	return 0 unless @_ || $@;
	my @error = @_ ? (@_) : ($@);
	my $fh = select STDERR;
	typed_output('error', map {s/\(\@INC contains\: (.*?)\)\s*//g; $_} @error);
	select $fh;
	1;
}

sub typed_output {
	my $type = shift;
	my @dinge = @_;
	return unless @dinge > 0;

	$type = $Zoidberg::CURRENT->{settings}{output}{$type} || $type;
	return 1 if $type eq 'mute';

	my $coloured;
	print "\e[$colours{$type}m" and $coloured = 1
		if exists $colours{$type}
		and $Zoidberg::CURRENT->{settings}{interactive} and $ENV{CLICOLOR};

	$dinge[-1] .= "\n" unless ref $dinge[-1];
	for (@dinge) {
		$_ = $_->scalar() if ref($_) eq 'Zoidberg::Utils::Output::Scalar';
		unless (ref $_) { print $_ }
		elsif (ref($_) eq 'ARRAY' and ! grep { ref($_) } @$_) { output_list(@$_) }
		elsif (ref($_) eq 'Zoidberg::Utils::Error') {
			if ($$_{debug}) { print map {s/^\$VAR1 = //; $_} Dumper $_ }
			else {
				next if $$_{silent} || $$_{printed}++;
				print $_->stringify(format => 'gnu');
			}
		}
		elsif (ref($_) =~ /Zoidberg/) {
			complain 'Cowardly refusing to dump object of class '.ref($_);
		}
		else { print map {s/^\$VAR1 = //; $_} Dumper $_ }
	}

	print "\e[$colours{reset}m" if $coloured;
	
	1;
}

sub output_list { # takes minimum number of rows, but fills cols first
	my (@items) = @_;
	my $width = $ENV{COLUMNS};

	return print join("\n", @items), "\n" unless $Zoidberg::CURRENT->{settings}{interactive};

	my $len = 0;
	$_ > $len and $len = $_ for map {s/\t/    /g; length $_} @items;
	$len += 2; # spacing
	return print join("\n", @items), "\n" if $width < (2 * $len);      # rows == items
	return print join('  ', @items), "\n" if $width > (@items * $len); # 1 row

	my $cols = int($width / $len ) - 1; # 0 based
	my $rows = int(@items / ($cols+1)); # 0 based ceil
	$rows -= 1 unless @items % ($cols+1); # tune ceil
	my @rows;
	for my $r (0 .. $rows) {
		my @row = map { $items[ ($_ * ($rows+1)) + $r] } 0 .. $cols;
		push @rows, join '', map { $_ .= ' 'x($len - length $_) } @row;
	}
	#print STDERR scalar(@items)." items, $len long, $width width, $cols+1 cols, $rows+1 rows\n";
	print join("\n", @rows), "\n";
}

sub output_sql { # kan vast schoner
	shift unless ref($_[0]) eq 'ARRAY';
	my $width = $ENV{COLUMNS};
	if (! $Zoidberg::CURRENT->{settings}{interactive} || !defined $width) {
		return (print join("\n", map {join(', ', @{$_})} @_)."\n");
	}
	my @records = @_;
	my @longest = ();
	@records = map {[map {s/\'/\\\'/g; "'".$_."'"} @{$_}]} @records; # escape quotes + safety quotes
	foreach my $i (0..$#{$records[0]}) {
		map {if (length($_) > $longest[$i]) {$longest[$i] = length($_);} } map {$_->[$i]} @records;
	}
	#print "debug: records: ".Dumper(\@records)." longest: ".Dumper(\@longest);
	my $record_length = 0; # '[' + ']' - ', '
	for (@longest) { $record_length += $_ + 2; } # length (', ') = 2
	if ($record_length <= $width) { # it fits ! => horizontal lay-out
		my $cols = floor($width / ($record_length+2)); # we want two spaces to saperate coloms
		my @strings = ();
		for (@records) {
			my @record = @{$_};
			for (0..$#record-1) { $record[$_] .= ', '.(' 'x($longest[$_] - length($record[$_]))); }
			$record[$#record] .= (' 'x($longest[$#record] - length($record[$#record])));
			if ($cols > 1) { push @strings, "[".join('', @record)."]"; }
			else { print "[".join('', @record)."]\n"; }
		}
		if ($cols > 1) {
			my $rows = ceil(($#strings+1) / $cols);
			foreach my $i (0..$rows-1) {
				for (0..$cols) { print $strings[$_*$rows+$i]."  "; }
				print "\n";
			}
		}
	}
	else { for (@records) { print "[\n  ".join(",\n  ", @{$_})."\n]\n"; } } # vertical lay-out
	return 1;
}

package Zoidberg::Utils::Output::Scalar;

our $VERSION = '0.981';

use overload
	'""'   => \&scalar,
	'bool' => \&error,
	'@{}'  => \&array,
	fallback => 'TRUE';

sub new    { bless \[@_[1,2,3]], $_[0] }

sub error  { my $s = ${ shift() }; $$s[0] }

sub scalar {
	my $s = ${ shift() };
	$$s[1] = join "\n", @{$$s[2]} if ! defined $$s[1] and $$s[2];
	return $$s[1];
}

sub array {
	my $s = ${ shift() };
	if (! defined $$s[2]) {
		$$s[2] = (ref($$s[1]) eq 'ARRAY') ?  $$s[1]  :
			  ref($$s[1])             ? [$$s[1]] : [ split /\n/, $$s[1] ];
	}
	return $$s[2];
}


1;

__END__

=head1 NAME

Zoidberg::Utils::Output - Zoidberg output routines

=head1 SYNOPSIS

	use Zoidberg::Utils qw/:output/;

	# use this instead of perlfunc print
	output "get some string outputted";
	output { string => 'or some data struct dumped' };

=head1 DESCRIPTION

This module provides some routines used by various
Zoidberg modules to output data.

Although when working within the Zoidberg framework this module should be used through
the L<Zoidberg::Utils> interface, it also can be used on it's own.

=head1 EXPORT

By default all of the below except C<typed_output>.

=head1 METHODS

=over 4

=item C<output(@_)>

Output a list of possibly mixed data structs as nice as possible.

A reference to an array of plain scalars may be outputted as a multicolumn list,
more complex data will be dumped using L<Data::Dumper>.

=item C<message(@_)>

Like C<output()> but tags data as a message, in non-interactive mode these may not 
be printed at all.

=item C<debug(@_)>

Like C<output()> tags the data as debug output, will only be printed when in debug mode.
Debug ouput will be printed to STDERR if printed at all.

=item C<complain(@_)>

Like C<output> but intended for error messages, data will be printed to STDERR.
Has some glue for error objects created by L<Zoidberg::Utils::Error>.
Prints C<$@> when no argument is given.

=item C<typed_output($type, @_)>

Method that can be used to define output types that don't fit in the above group.
C<$type> must be a plain string that is used as output 'tag'.

=item C<output_is_captured($type, @_)>

Method that returns a boolean that tells whether output is captured or not.
This can be used to make terminal output different from data struct output.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>

=cut

