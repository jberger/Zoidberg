package Zoidberg::Fish;

our $VERSION = '0.98';

use strict;
use Zoidberg::Utils 'error';

our $ERROR_CALLER = 1;

=head1 NAME

Zoidberg::Fish - Base class for loadable Zoidberg plugins

=head1 SYNOPSIS

  package My_Zoid_Plugin;
  use base 'Zoidberg::Fish';

  FIXME some example code

=head1 DESCRIPTION

Once this base class is used your module smells like fish -- Zoidberg WILL eat it.
It supplies stub methods for hooks and has some routines to simplefy the interface to
Zoidberg. One should realize that the bases of a plugin is not the module but
the config file. Any module can be used as plugin as long as it's properly configged.
The B<developer manual> should describe this in more detail.

FIXME update the above text

=head1 METHODS

=over 4

=item C<new($shell, $zoidname)>

Simple constructor that bootstraps same attributes. When your module smells like fish
Zoidberg will give it's constructor two arguments, a reference to itself and the name by
which your module is identified. From this all other config can be deducted.

	# Default attributes created by this constructor:
 	
	$self->{shell}     # a reference to the parent Zoidberg object
	$self->{zoidname}  # name by which your module is identified
	$self->{settings}  # reference to hash with global settings
	$self->{config}    # hash with plugin specific config

=cut

=item C<init()>

To be overloaded, will be called directly after the constructor. 
Do things you normally do in the constructor like loading files, opening sockets 
or setting defaults here.

=cut

sub new {
	my ($class, $zoid, $name) = @_;
	my $self = {
		parent	 => $zoid, # DEPRECATED !
		shell    => $zoid,
		zoidname => $name,
		settings => $zoid->{settings},
		config	 => $zoid->{settings}{$name},
		round_up => 1,
	};
	bless $self, $class;
}

sub init {}

# ########## #
# some stubs #
# ########## #

=item C<config()>

=item C<shell()>

These methods return a reference to the attributes by the same name.

=cut

sub config { $_[0]{config} }

sub shell  { $_[0]{shell}  }

=item C<plug()>

A stub doing absolutely nothing, but by calling it from
a dispatch table the plugin is loaded.

=item C<unplug()>

Removes this plugin from the various dispatchtables, and deletes the object.

=cut

sub plug { 1 } # when called the module will be loaded

sub unplug { delete $_[0]->{shell}{objects}{$_[0]{zoidname}} }

# ####################### #
# event and command logic #
# ####################### #

=item C<broadcast($event_name, @_)>

Broadcast an event to whoever might be listening.

=cut

sub call { die 'deprecated routine used' }

sub broadcast {
	my $self = shift;
	$self->{shell}->broadcast(@_);
}

=item C<< add_events({ event => sub { .. } }) >>

=item C<add_events(qw/event1 event2/)>

Used to add new event hooks.
In the second form the events are hooked to call the likely
named subroutine in the current object.

=item C<wipe_events(qw/event1 event2/)>

Removes an event. Wipes the stacks for the named events
of all routines belonging to this plugin.

=item C<< add_commands({ command => sub { .. } }) >>

=item C<add_commands(qw/command1 command2/)>

Used to add new builtin commands.
In the second form the commands are hooked to call the likely
named subroutine in the current object.

=item C<wipe_commands(qw/command1 command2/)>

Removes a command. Wipes the stacks for the named commands
of all routines belonging to this plugin.

=item C<add_expansion(regex_ref => sub { ... })>

TODO

=item C<wipe_expansions()>

TODO

=cut

sub add_events { # get my events unless @_ ?
	my $self = shift;
	error 'add_events needs args' unless @_;
	my %events;
	if( my $reftype = ref($_[0]) ) {
		%events = ( $reftype eq 'HASH' ) ? %{ shift() } : @{ shift() };
	} else {
		%events = (map {($_ => "->$$self{zoidname}->$_")} @_);
	}
	$$self{shell}{events}{$_} = [$events{$_}, $$self{zoidname}]
		for keys %events;
}

sub wipe_events {
	my $self = shift;
	error 'wipe_events needs args' unless @_;
	tied( %{$$self{shell}{events}} )->wipe( $$self{zoidname}, @_ );
}

sub add_commands { # get my commands unless @_ ?
	my $self = shift;
	error 'add_commands needs args' unless @_;
	my %commands; 
	if ( my $reftype = ref($_[0]) ) {
		%commands = ( $reftype eq 'HASH' ) ? %{ shift() } : @{ shift() };
	} else {
		%commands = (map {($_ => "->$$self{zoidname}->$_")} @_);
	}
	$$self{shell}{commands}{$_} = [$commands{$_}, $$self{zoidname}]
		for keys %commands;
}

sub wipe_commands {
	my $self = shift;
	error 'wipe_commands needs args' unless @_;
	tied( %{$$self{shell}{commands}} )->wipe( $$self{zoidname}, @_ );
}

sub add_expansion {
	todo()
}

sub wipe_expansions {
	todo()
}

# ########### #
# other stuff #
# ########### #

=item C<add_context(%config)>

See man L<zoiddevel>(1) for the context configuration details.

=cut

sub add_context { # ALERT this logic might change
	my $self = shift;
	my %context = ref($_[0]) ? (%{shift()}) : (splice @_);
	my $cname = delete($context{name}) || $$self{zoidname};
	my $fp = delete($context{from_package});
	my $nw = delete($context{no_words});
	for (values %context) { $_ = "->$$self{zoidname}->$_" unless ref $_ or /^\W/ }

	if ($fp) { # autoconnect
		$self->can($_) and $context{$_} ||= "->$$self{zoidname}->$_"
			for qw/word_list handler completion_function intel filter parser word_expansion/;
	}

	for (qw/filter word_list word_expansion/) { # stacks
		$self->{shell}{parser}{$_} = delete $context{$_}
			if exists $context{$_};
	}

	if ($nw) { # no words
		push @{$$self{shell}{no_words}}, $cname;
	}

	$self->{shell}{parser}{$cname} = [\%context, $$self{zoidname}]
		if keys %context; # maybe there were only stacks
	return $cname;
}

=item C<ask($question, $default)>

Get interactive input. The default is optional.
If the default is either 'Y' or 'N' a boolean value is returned.

=cut

sub ask { # FIXME FIXME FIXME hide chars and no hist whe $pass FIXME FIXME FIXME
	my ($self, $quest, $def, $pass) = @_;
	$quest =~ s/\s*$/ /;
	$quest .= ($def =~ /^n$/i) ? '[yN] '
		: ($def =~ /^y$/i) ? '[Yn] ' : "[$def] " if $def;
	my $ans = $$self{shell}->builtin('readline', $quest);
	$ans =~ s/^\s*|\s*$//g;
	$ans = $def unless length $ans;
	return( ($def =~ /^[ny]$/i) ? ($ans =~ /y/i) : $ans );
}


=item C<round_up()>

Is called when the plugin is unloaded or when a sudden DESTROY occurs.
To be overloaded, do things like saving files or closing sockets here.

=cut

sub round_up {} # put shutdown sequence here -- like saving files etc.

sub DESTROY {
	my $self = shift;
	$self->round_up if $$self{round_up} && $$self{shell}{round_up};
}

1;

__END__

=back

=head1 AUTHOR

R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Raoul L. Zwart and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>,
L<Zoidberg::Shell>,
L<Zoidberg::Utils>,
L<http://github.com/jberger/Zoidberg>

=cut
