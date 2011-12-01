package Zoidberg::DispatchTable;

our $VERSION = '0.97';

use strict;
use Zoidberg::Utils qw/debug bug error/;
use Exporter::Tidy all => [qw/stack wipe tag tags/];

our $ERROR_CALLER = 1; 

# reserved keys _AUTOLOAD and _META

# $self->[0] hash with arrays of dispatch strings/refs
# $self->[1] hash with arrays of tags
# $self->[2] object ref
# $self->[3] object can parent bit
# $self->[4] array with keys to keep them in order
# $self->[5] iteration index for keys()

# keys are kept in order to avoid inconsistencies
# for example when iterating trough {parser}

sub new { # create a blessed AND tie'ed hash
	my $class = shift;
	my %hash;
	tie %hash, $class, @_;
	bless \%hash, $class;
}

sub TIEHASH  {
	my $class = shift;
	my $ref = shift || error 'need object ref to tie hash';
	# $ref is either array ref or object ref
	my $self = (ref($ref) eq 'ARRAY')
		? $ref
		: [{}, {}, $ref, $ref->can('parent'), [], 0];
	bless $self, $class;
	while (my $hash = shift @_) {
		$self->STORE($_, $$hash{$_}) for keys %$hash;
	}
	return $self;
}

sub STORE {
	my ($self, $key, $value) = @_;
	my $tag = 'undef';
	($value, $tag) = @$value if ref($value) eq 'ARRAY';

	my $t = ref $value;
	if ($t eq 'HASH') {
		unless (tied $value) { # recurs tie'ing
			tie %$value, __PACKAGE__, $$self[2], $value;
			# be careful to reuse same ref - else perl bugs :(
		}
		# else just store the tied hash
	}
	elsif (! $t) {
		$value =~ s/(^\s*|\s*$)//g;
		error "Can't use ==>$value<== as subroutine."
			if ! length $value
			or $value =~ /^\$/; # no vars
	}
	elsif ($t ne 'CODE') { bug "Can't store ref of type $t in DispatchTable" }

	push @{$self->[0]{$key}}, $value;
	push @{$self->[1]{$key}}, $tag;
	push @{$self->[4]}, $key;
}

sub add {
	my $self = tied %{ shift() };
	$self->STORE(@_);
}

sub FETCH {
	my ($self, $key) = @_;
	if ( exists $$self[0]{$key} and scalar @{$$self[0]{$key}} ) {
		$$self[0]{$key}[-1] = $self->convert($self->[0]{$key}[-1])
			unless ref $self->[0]{$key}[-1];
		return $self->[0]{$key}[-1];
	}
	elsif ($self->EXISTS('_AUTOLOAD')) {
		my $sub;
		for (@{$self->[0]{_AUTOLOAD}}) {
	        	$sub = $_->($key);
        		next unless $sub;
		        $self->STORE($key, $sub) unless $self->EXISTS($key);
        		return $self->FETCH($key);
		}
	}
	return undef;
}

sub convert {
	my ($self, $ding) = @_;

	if ($ding =~ /^\s*sub\s*{.*}\s*$/) { # undocumented hack
		debug "going to eval: $ding";
		my $closure = eval $ding;
		die if $@;
		return sub { $closure->($$self[2], @_) };
	}

        $ding =~ s#^->((\w+)->)?#
		( $self->[3] ? q/parent->/         : '' ) .
		( $1         ? qq/{objects}{$2}->/ : '' )
	#e;

	if ($ding =~ /\(\s*\)$/s) { $ding =~ s/\s*\)$/\@_\)/ }
        elsif ($ding =~ /\(.*\)$/s) { $ding =~ s/\)$/, \@_\)/ }
	else { $ding .= '(@_)' }

	debug "going to eval: sub { \$self->[2]->$ding }";
	my $sub = eval "sub { \$\$self[2]->$ding }";
	die if $@;
	return $sub;
}

sub EXISTS { exists $_[0][0]->{$_[1]} and scalar @{$_[0][0]->{$_[1]}} }

sub DELETE { # doesn't really delete, merely pops
	my ($self, $key) = @_;
	return undef unless exists $self->[0]{$key};

	pop @{$self->[1]{$key}};
	my $re = pop @{$self->[0]{$key}};
	
	unless (scalar @{$self->[0]{$key}}) {
		delete $self->[0]{$key};
		delete $self->[1]{$key};
		@{$self->[4]} = grep {$_ ne $key} @{$self->[4]};
	}
	
	return $re;
}

sub pop {
	my $self = tied %{ shift() };
	$self->DELETE(@_);
}

sub CLEAR    { 
	%{$_[0][0]} = ();
	%{$_[0][1]} = ();
	@{$_[0][4]} = ();
	  $_[0][5]  =  0;
}

sub FIRSTKEY {
	$_[0][5] = 0;
	goto \&NEXTKEY
}

sub NEXTKEY  {
	my $self = shift;
	if ($$self[5] > $#{$$self[4]}) {
		$$self[5] = 0;
		return wantarray ? () : undef;
	}
	elsif (wantarray) { # ($key, $value) = each(%table)
		my $key = $$self[4][$$self[5]++];
		return $key, $self->FETCH($key);
	}
	else { return $self->[4][$$self[5]++] } # for $key (keys %table)
}

sub stack {
	my $self = tied %{ shift() };
	my ($key, $use_tag) = @_;
	return () unless exists $$self[0]{$key};
	for (@{$self->[0]{$key}}) { $_ = $self->convert($_) unless ref $_ }
	return map [ $$self[0]{$key}[$_], $$self[1]{$key}[$_] ], (0..$#{$$self[0]{$key}})
		if $use_tag;
	return @{$self->[0]{$key}};
}

sub tag {
	my $self = tied %{ shift() };
	my $key = shift;
	return undef unless exists $$self[1]{$key};
	return $$self[1]{$key}[-1];
}

sub tags {
	my $self = tied %{ shift() };
	my $key = shift;
	return undef unless exists $$self[1]{$key};
	return @{$self->[1]{$key}};
}

sub wipe {
	my $self = tied %{ shift() };
	my ($tag, @keys) = @_;
	@keys = keys %{$self->[0]} unless scalar @keys;
	my %old;
	for my $key (@keys) {
		for (my $i = 0; $i < @{$self->[1]{$key}}; $i++) {
			next unless $self->[1]{$key}[$i] eq $tag;
			$old{$key} = [$self->[0]{$key}[$i], $tag];
			$self->[0]{$key}[$i] = undef;
			$self->[1]{$key}[$i] = undef;
		}
		@{$self->[0]{$key}} = grep {defined $_} @{$self->[0]{$key}};
		@{$self->[1]{$key}} = grep {defined $_} @{$self->[1]{$key}};
		unless (scalar @{$self->[0]{$key}}) {
			delete $self->[0]{$key};
			delete $self->[1]{$key};
			@{$self->[4]} = grep {$_ ne $key} @{$self->[4]};
		}
	}
	return \%old;
}

1;

__END__

=head1 NAME

Zoidberg::DispatchTable - Class to tie dispatch tables

=head1 SYNOPSIS

	use Zoidberg::DispatchTable;

	my $table = Zoidberg::DispatchTable->new(
		$self, { cd => '->Commands->cd' }
	);

	# The same as $self->parent->{objects}{Commands}->cd('..') if
	# a module can('parent'), else the same as $self->Commands->cd('..')
	$$table{cd}->('..');

	$$table{ls} = q{ls('-al')}

	# The same as $self->ls('-al', '/data')
	$$table{ls}->('/data');

=head1 DESCRIPTION

This module provides a tie interface for converting config strings
to CODE references. It takes an object references (C<$self>) 
as starting point for resolving subroutines.
If the object has a method C<parent()> the refrence returned by this 
method is used as the root for resolving subroutines, else the object
itself is used as root.
The root is expected to contain a hash C<{objects}> (possibly of the 
class L<Zoidberg::PluginHash>) with references to "child" objects.

Strings are converted to CODE references at first use to save time
at initialisation.

The following strings are supported:

  String              Interpretation
  ----------          -----------------
  sub                 Sub of the reference object
  ->sub               Sub of the root object
  ->sub(qw/f00 b4r/)  Sub of the root object with arguments
  ->object->sub       Sub of a child object of the root
  ->sub()->..         Sub of the root object

You can store either config strings or CODE references in the table.

The tables is transparent to CODE references, they are used as given.
( An earlier version of this module did currying .. this behaviour is altered. )

If you store an ARRAY ref it is expected to be of the form C<[$value, $tag]>,
where C<$tag> is an identifier used for handling selections of the table.
The $value can again be a string or CODE ref.

If you store a HASH ref it will be tied recursively as a DispatchTable.

Keys are kept in the order they are first added, thus C<keys(%table)> will always
return the same order. This is to keep zoid's plugins in the order they are added.
Also for each key a stack is used. Deleting a key only pops it's stack.

I< This modules doesn't check for security issues, it just runs arbitrary code. >

=head1 EXPORT

This module can export the methods C<wipe>, C<stack> and C<tags>.

=over 4

=item add

=item pop

=item C<wipe(\%table, $tag, @keys)>

Wipes entries with tag C<$tag> from given set of kaeys or from the whole
table.

=item C<stack(\%table, $key, $tags)>

Returns the whole stack for an given key, useful to loop trough stacks.
C<$tags> is a boolean, when true all items are returned as a sub array of CODE ref
with tag.

=item C<tag(\%table, $key)>

Returns the tag for the given key.

=item C<tags(\%table, $key)>

Returns an array of all tags for given key.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>

=cut

