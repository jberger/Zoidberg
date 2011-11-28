
package Zoidberg::Utils::Error;

our $VERSION = '0.96';

use strict;
use UNIVERSAL qw/isa can/;
use Exporter::Tidy default => [qw/error bug todo/];
use overload
	'""' => \&stringify,
	'eq' => sub { $_[0] },
	fallback => 'TRUE';

our $Scope = $0;
$Scope =~ s#.*/##;

# ################ #
# Exported methods #
# ################ #

sub error {
	my @caller = caller;
	
	if ($@ && !@_) { # make it work more like die
		die $@->PROPAGATE(@caller[1,2]) if can $@, 'PROPAGATE';
		unshift @_, PROPAGATE({}, @caller[1,2]), $@;
	}

	my $error = bless {};

	for (@_) { # compiling the error here
		if (isa $_, 'HASH') { %$error = (%$error, %$_) }
		else { $$error{string} .= $_ }
	}

	unless ($$error{string}) {
		$$error{string} =
			  $$error{is_bug}  ? 'This is a bug'
			: $$error{is_todo} ? 'Something TODO here' : 'Error' ;
	}
	elsif ($$error{string} =~ s/\(\@INC contains\: (.*?)\)\s*//g) { # make it less verbose
		$$error{INC} = $1;
	}

	# trace stack
	$$error{stack} ||= [];
	{
		no strict 'refs';
		@caller = caller(${$caller[0].'::ERROR_CALLER'}) 
			if ${$caller[0].'::ERROR_CALLER'};
		push @{$$error{stack}}, \@caller;

		if ( # debug code
			$$error{debug} = ${$caller[0].'::DEBUG'}
				|| $Zoidberg::CURRENT->{settings}{debug}
		) {
			push @{$$error{stack}}, [ (caller $_)[0..2] ]
				for (1..$$error{debug});
		}
	}
	
	if (defined $Scope) { # set fake caller
		$$error{scope} ||= ref($Scope)
			? [ $$Scope[0], $$Scope[1] || $caller[2] ]
			: [ $Scope ];
	}

	die $error;
}

sub bug {
	unshift @_, { is_bug => 1 };
	goto \&error;
}

sub todo {
	unshift @_, { is_todo => 1 };
	goto \&error;
}

# ############## #
# Object methods #
# ############## #

sub stringify {
	# TODO verbosity optie
	no warnings; # lots of stupid warnings here (due to 'overload' ?)
	my $self = shift;
	my %opt = @_;
	my $string;
	if ($opt{format} eq 'gnu') {
		$string = join( ': ', grep {defined $_} 
			( $$self{scope}  ? (@{$$self{scope}}) : (@{$$self{stack}[0]}) ),
			( $$self{is_bug} ? 'BUG' : $$self{is_todo} ? 'TODO' : undef   ),
			$$self{string} ) . "\n" ;
	}
	else {
		$string = ($$self{is_bug} ? 'BUG: ' : $$self{is_todo} ? 'TODO: ' : '')
			. $self->{string};
		$string .= qq# at $$self{stack}[0][1] line $$self{stack}[0][2]\n# 
				unless $string =~ /\n$/;
		if (exists $$self{propagated} and ref $$self{propagated}) {
			$string = PROPAGATE($string, @$_) for @{$self->{propagated}};
		}
	}
	return $string;
}

sub PROPAGATE { # see perldoc -f die
	my ($self, $file, $line) = @_;
	($file, $line) = ( caller() )[1,2] unless $file or $line;
	if (ref $self) {
		$self->{propagated} ||= [];
		push @{$self->{propagated}}, [$file, $line];
	}
	else { $self .= "\t...propagated at $file line $line\n" }
	return $self;
}


1;

__END__

=head1 NAME

Zoidberg::Utils::Error - OO error handling

=head1 SYNOPSIS

	use Zoidberg::Utils qw/:error/;
	
	sub some_command {
		error "Wrong number of arguments"
			unless scalar(@_) == 3;
		# do stuff
	}

	# this raises an object oriented exception

=head1 DESCRIPTION

This library supplies the methods to replace C<die()>.
These methods raise an exception but passing a object containing both the error string
and caller information. Thus, when the exception is caught, more subtle error messages can be produced
depending on for example verbosity settings.

If the global variable C<$ERROR_CALLER> is set in a package using this library, all errors
will pretend to originate from the call-frame identified by the number of the variable.
Setting C<$ERROR_CALLER> to 1 will result in L<Carp> like behaviour.

Although when working within the Zoidberg framework this module should be used through
the L<Zoidberg::Utils> interface, it also can be used on it's own.

=head1 EXPORT

By default C<error()>, C<bug()> and C<todo()>. When using the L<Zoidberg::Utils> interface
you also get C<complain()>, which actually belongs to L<Zoidberg::Utils::Output>.

=head1 METHODS

=head2 Exported methods

=over 4

=item C<error($error, ..)>

Raises an exception which passes on C<\%error>.

=item C<bug($error, ..)>

Like C<error()>, but with C<is_bug> field set.

=item C<todo($error, ..)>

Like C<error()>, but with C<is_todo> field set.

=back

=head2 Object methods

=over 4

=item C<stringify(%opts)>

Returns an error string.

Known options:

=over 4

=item format

Types 'gnu' and 'perl' are supported. 
The format 'perl' is the default, 'gnu' is used by zoidberg's C<complain()> function.

=back

=item C<PROPAGATE($file, $line)>

Is automaticly called by C<die()> when you use for example:

	use Zoidberg::Utils::Error;

	eval { error 'test' }
	die if $@; # die is called without explicit argument !

See also L<perlfunc/die>.

=back

=head1 ATTRIBUTES

The exception raised can have the folowing attributes:

=over 4

=item string

Original error string.

=item scope

The global C<$Zoidberg::Utils::Error::Scope> at the time of the exception.
This is used to hide the real caller information in the gnu formatted
error string with for example the name of a builtin command.

=item package

Calling package.

=item file

Source file where the exception was raised.

=item line

Line in source file where the exception was raised.

=item debug

The calling package had the global variable C<$DEBUG> set to a non-zero value.

=item stack

When debug was in effect, the caller stack is traced for a number of frames 
equal to the value of the debug variable and put in the stack attribute.

=item is_bug

This exception should never happen, if it does this is considered a bug.

=item is_todo

This exception is raised because some feature isn't yet implemented.

=item propagated

Array of arrays containg information about file and line numbers where
this error was propagated, see L</PROPAGATE>.

=back

=head2 Overloading

When the methods are given a hash reference as one of there arguments
this hash overloads the default values of C<%error>. Thus it is possible to fake
for example the calling package, or add meta data to an exception.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2003 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Utils>,
L<http://www.gnu.org/prep/standards_15.html#SEC15>

=cut

