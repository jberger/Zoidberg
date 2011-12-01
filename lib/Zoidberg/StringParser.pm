package Zoidberg::StringParser;

# Hic sunt leones.

our $VERSION = '0.97';

use strict;
no warnings; # can't stand the nagging
use Zoidberg::Utils qw/debug error bug/;

our $ERROR_CALLER = 1;

# TODO :
# esc per type ?

# how bout more general state machine approach,
#     making QUOTE and NEST operations like CUT, POP and RECURS

# grammar can be big hash (sort keys on length) .. how to deal with regexes than ?
#  ... optimise for normal string tokens, regexes are the exception
#  need seperate hashes for overloading

# how bout ->for(gram, string, int, sub) ? exec sub on token with most parser vars in scope
#   %state ?

sub new {
	my $class = shift;
	my $self = {
		base_gram  => shift || {},
		collection => shift || {},
		settings   => shift || {},
	};
	bless $self, $class;
	return $self;
}

sub split {
	my ($self, $gram, $input, $int) = @_;
	$int--; # 1 based => 0 based

	$$self{broken} = undef; # reset error

	debug "splitting with $gram";
	unless (ref $gram) {
		error "No such grammar: $gram" unless $$self{collection}{$gram};
		$gram = [$$self{collection}{$gram}]
	}
	elsif (ref($gram) eq 'ARRAY') {
		my $error;
		$gram = [ map {
			ref($_) ? $_ : ($$self{collection}{$_} || $error++)
		} @$gram ];
		error "No such grammar: $_" if $error;
	}
	else { $gram = [$gram] } # hash or regex
	unshift @$gram, $$self{base_gram};

	my ($expr, $types);
	($gram, $expr, $types) = $self->_prepare_gram($gram);
#	use Data::Dumper; print STDERR Dumper $gram, $expr, $types;

	my $string;
	if (ref($input) eq 'ARRAY') { $string = shift @$input }
	else { ($string, $input) = ("$input", []) } # quotes in case of overload

	return unless length $string or @$input;

	my ($block, @parts, @open, $i, $s_i); # $i counts splitted parts, $s_i the stack size

	PARSE_TOKEN:
	debug 'splitting string: '.$string;

	my ($token, $type, $sign);
	while ( !$token && $string =~ s{\A(.*?)($expr\z)}{}s ) {
		$block .= $1 if length $1;
		$sign = $2;

		my $i = 0;
		($_ eq $2) ? last : $i++ for ($3, $4, $5);
		$type = $$types[$i];

		last unless length $sign or length $string; # catch the \z

		if ($type eq 'd_esc') {
			debug "block: ==>$block<== token: ==>$sign<== type: $type";
			$block .= $sign;
			next;
		}

		# fetch token
		my $item;
		my ($slice) = grep exists($$_{$type}), reverse @$gram;
		if (ref($$slice{$type}[1]) eq 'ARRAY') { # for loop probably faster
			($item) = map $$_[1], 
				grep {ref($$_[0]) ? ($sign =~ $$_[0]) : ($sign eq $$_[0])}
				@{$$slice{$type}[1]}
		}
		else { $item = $$slice{$type}[1]{$sign} }
		debug "block: ==>$block<== token: ==>$sign<== type: $type item: $item";
		$item = $sign if $item eq '_SELF';

		if (exists $$slice{s_esc} and $1 =~ /$$slice{s_esc}$/) {
			debug 'escaped token s_esc: '.$$slice{s_esc};
			$block =~ s/$$slice{s_esc}$//
		       		if $type eq 'tokens' and ! $$self{settings}{no_esc_rm};
			$block .= $sign;
			next;
		}

		if ($type eq 'tokens') {
			unless ($s_i) {
				if (ref $item) { # for $() matching tactics
					debug 'push stack (tokens)';
					push @$gram, $item;
					$s_i++;
					($gram, $expr, $types) = $self->_prepare_gram($gram);
					@open = ($sign, $type);
					$token = $$gram[-1]{token};
				}
				else { $token = $item }
			}
			else {
				if ($item eq '_POP') {
					$block .= $sign;
					debug "pop stack ($item)";
					pop @$gram;
					$s_i--;
				}
				elsif ($item eq '_CUT') { # for $() matching
					$token = $item;
					debug "cut stack ($item)";
					splice @$gram, -$s_i;
					$s_i = 0;
				}
				else { bug "what to do with $item !?" }
				($gram, $expr, $types) = $self->_prepare_gram($gram);
			}
		}
		else { # open nest or quote
			$block .= $sign;
			unless (ref $item) {
				if ($item eq '_REC') { $item = {} } # recurs UGLY
				else { # generate a grammar on the fly
					$item = ($type eq 'nests')
						? {
							tokens => {$item => '_POP'},
							nests => {$sign => '_REC'},
						} : {
							tokens => {$item => '_POP'},
							quotes => {$sign => '_REC'},
							nests => {},
						} ;
				}
			}
			# else if item is ref => item is grammar
			debug "push stack ($type)";
			push @$gram, $item;
			$s_i++;
			($gram, $expr, $types) = $self->_prepare_gram($gram);
			@open = ($sign, $type);
		}
		last unless length $string;
	}

	if (length $block) {
		my $part = $block; # force copy
		push @parts, \$part;
	}
	if ($token and $token ne '_CUT') { push @parts, $token }
	$block = $token = undef;

	if (($s_i or ++$i != $int) and length($string) || scalar(@$input)) {
		$string = shift @$input unless length $string;
		goto PARSE_TOKEN;
	}
	elsif ($i == $int) {
		my $part = join '', $string, @$input;
		push @parts, \$part;
	}

	if ($s_i) { # broken
		debug 'stack not empty';
		$open[1] =~ s/s$// ;
		$$self{broken} = "Unmatched $open[1] at end of input: $open[0]";
		error $$self{broken} unless $$self{settings}{allow_broken};
		pop @$gram for 1 .. $s_i;
	}

	return grep defined($_), map {ref($_) ? $$_ : $_} @parts
		if $$gram[-1]{was_regexp} && ! $$self{settings}{no_split_intel};
	return grep defined($_), @parts;
}

sub _prepare_gram { # index immediatly here
	my ($self, $gram) = @_;
	my %index;
	for my $ref (@$gram) { # prepare grammars for usage
		if (ref($ref) eq 'Regexp') {
			$ref = {tokens => [[$ref, '_CUT']], was_regexp => 1};
		}
		elsif (ref($ref) ne 'HASH') {
			error 'Grammar has wrong data type: '.ref($ref)."\n";
		}
		
		unless ($$ref{prepared}) {
			if (exists $$ref{esc}) {
				$$ref{s_esc} = ref($$ref{esc}) ? $$ref{esc}
					: quotemeta $$ref{esc};			# single esc regexp
				$$ref{d_esc} = '('.($$ref{s_esc}x2).')|';	# double esc regexp
			}
			elsif (! exists $$ref{s_esc} and exists $index{s_esc}) {
				$$ref{s_esc} = $index{s_esc};
			}

			for (qw/tokens nests quotes/) {
				next unless exists $$ref{$_};
				my $expr = (ref($$ref{$_}) eq 'ARRAY')
					? join( '|', map {
						ref($$_[0]) ? $$_[0] : quotemeta($$_[0])
					} @{$$ref{$_}} )
					: join( '|', map { quotemeta($_) } keys %{$$ref{$_}} ) ;
				$expr = $expr ? '('.$expr.')|' : '';
				$$ref{$_} = [$expr, $$ref{$_}];
			}
			$$ref{prepared}++;
		}

		$index{$_} = $$ref{$_}[0] for grep exists($$ref{$_}), qw/tokens nests quotes/;
		$index{$_} = $$ref{$_} for grep exists($$ref{$_}), qw/s_esc d_esc/;
	}
	
	my ($expr, @types) = ('');
	for (qw/d_esc tokens nests quotes/) {
		next unless length $index{$_};
		push @types, $_;
		$expr .= $index{$_};
	}
	return $gram, $expr, \@types;
}

1;

__END__

=head1 NAME

Zoidberg::StringParser - Simple string parser

=head1 SYNOPSIS

	my $base_gram = {
	    esc => '\\',
	    quotes => {
	        q{"} => q{"},
	        q{'} => q{'},
	    },
	};

	my $parser = Zoidberg::StringParser->new($base_gram);

	my @blocks = $parser->split(
	    qr/\|/, 
	    qq{ls -al | cat > "somefile with a pipe | in it"} );

	# @blocks now is: 
	# ('ls -al ', ' cat > "somefile with a pipe | in it"');
	# So it worked like split, but it respected quotes

=head1 DESCRIPTION

This module is a simple syntax parser. It originaly was designed 
to work like the built-in C<split> function, but to respect quotes.
The current version is a little more advanced: it uses user defined 
grammars to deal with delimiters, an escape char, quotes and braces.

Yes, I know of the existence of L<Text::Balanced>, but I wanted to do this the hard way :)

I<All grammars and collections of grammars should be considered PRIVATE when used by a Z::SP object.>

=head1 EXPORT

None by default.

=head1 GRAMMARS

TODO

=over 4

=item esc

FIXME

=back

=head2 Collection

The collection hash is simply a hash of grammars with the grammar names as keys.
When a collection is given all methods can use a grammar name instead of a grammar.

=head2 Base grammar

This can be seen as the default grammar, to use it leave the grammar undefined when calling 
a method. If this base grammar is defined I<and> you specify a grammar at a method call, 
the specified grammar will overload the base grammar.

=head1 METHODS

=over 4

=item C<new(\%base_grammar, \%collection, \%settings)>

Simple constructor. See L</Collection>, 
L</Base grammar> and  L</settings> for explanation of the arguments.

=item C<split($grammar, $input, $int)>

Splits C<$input> as specified by C<$grammar>,

C<$input> can be either a string or a reference to an array of strings.
Such a array reference is used as provided, so it should be possible to use
for example tied arrays here.

C<$int> is an optional arguments specifying the maximum number of parts the input
should be splitted in. Remaining strings are joined and returned as the last part.
If you use a grammar with named tokens these are not counted as a part of the string.

Blocks will by default be passed as scalar refs (unless the grammar's meta function altered them)
and tokens as scalars. To be a little compatible with C<CORE::split> all items (blocks and tokens)
are passed as plain scalars if C<$grammar> is or was a Regexp reference.
( This behaviour can be faked by giving your grammr a value called 'was_regexp'. )
This behaviour is turned off by the L</no_split_intel> setting.

=back

=head2 settings

The C<%settings> hash contains options that control the  general behaviour of the parser.
Supported settings are:

=over 4

=item allow_broken

If this value is set the parser will not throw an exception if for example 
an unmatched quote occurs

=item no_esc_rm

Boolean that tells the parser not to remove the escape char when an escaped token
is encountered. Double escapes won't be replaced either. Usefull when a string needs 
to go through a chain of parsers.

=item no_split_intel

Boolean, disables "intelligent" behaviour of C<split()> when set.

=back

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Contains some code derived from Tie-Hash-Stack-0.09 by Michael K. Neylon.

=head1 SEE ALSO

L<Zoidberg>, L<Text::Balanced>

=cut

