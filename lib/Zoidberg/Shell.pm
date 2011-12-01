package Zoidberg::Shell;

our $VERSION = '0.97';

use strict;
use vars qw/$AUTOLOAD/;
use Zoidberg::Utils qw/:error :output path getopt/;
use Exporter::Tidy
	default	=> [qw/AUTOLOAD shell command builtin/],
	command	=> [qw/shell command builtin/],
	jobs    => [qw/job @JOBS/],
	data	=> [qw/alias unalias set setting/],
	other	=> [qw/source readpipe/];

our @JOBS;
tie @JOBS, 'Zoidberg::Shell::JobsArray';

sub new { 
	shift; #class
	eval 'use Zoidberg';
	die if $@;

	# reformat some settings
	my %obj = @_;
	my $set = $obj{settings} || {};
	$$set{rcfiles} = [] if exists $$set{norc} and delete $$set{norc};
	$$set{interactive} = (-t STDIN and -t STDOUT)
		unless defined $$set{interactive};
	$obj{settings} = $set;

	Zoidberg->new(%obj);
}

sub current { return $Zoidberg::CURRENT }

sub any {
	goto &new unless $Zoidberg::CURRENT;
	return $Zoidberg::CURRENT;
}

sub _self { ( eval{ $_[0]->isa( __PACKAGE__ ) } ) ? shift : $Zoidberg::CURRENT }

# ################ #
# Parser interface #
# ################ #

sub AUTOLOAD {
	## Code inspired by Shell.pm ##
	my $cmd = (split/::/, $AUTOLOAD)[-1];
	return undef if $cmd eq 'DESTROY';
	shift if ref($_[0]) eq __PACKAGE__;
	debug "Zoidberg::Shell::AUTOLOAD got $cmd";
	@_ = ([{plain_words => 1}, $cmd, @_]); # force words
	goto \&shell;
}

sub shell { # FIXME FIXME should not return after ^Z
	my $self = &_self;
	my $meta = (ref($_[0]) eq 'HASH') ? shift : {};
	my $pipe = ($_[0] =~ /^-\||\|-$/) ? shift : undef ;
	todo 'pipeline syntax' if $pipe;
	my $save_error = $$self{error};
	$$self{fg_job} ||= $self;
	$$meta{capture} = defined wantarray;
	$$meta{wantarray} = wantarray;
	local $$self{_settings}{output}{error} = 'mute'
		if delete $$meta{die_silently};
	my @re;
	if (grep {ref $_} @_) { @re = $$self{fg_job}->shell_list($meta, @_) }
	elsif (@_ > 1)        { @re = $$self{fg_job}->shell_list($meta, \@_) }
	else                  { @re = $self->shell_string($meta, @_) }
	$@ = $$self{error};
	$$self{error} = $save_error;
	_return($@, @re);
}

sub _return { # fairly complex output logic :S
	# the heuristic is that list context is the fastest .. can this be optimised further ?
	my $error = shift() ? 0 : 1;
	unless (@_) { return Zoidberg::Utils::Output::Scalar->new($error, '') }
	elsif (wantarray) {
		return map { # try to do the same list heuristics as utils::output
			(ref($_) eq 'ARRAY' and ! grep ref($_), @$_) ? (@$_) : $_
		} @_;
	}
	elsif (! grep ref($_), @_) { # only strings
		return Zoidberg::Utils::Output::Scalar->new($error, join('', @_)) ;
	}
	else { # one or more refs in @_
		if (@_ == 1) { # must be ref
			return( (ref($_[0]) eq 'ARRAY' and ! grep ref($_), @{$_[0]})
				? Zoidberg::Utils::Output::Scalar->new($error, undef, shift())
				: Zoidberg::Utils::Output::Scalar->new($error, shift()       )  ) ;
		}
		else { # mixed data - hope we get it right
			return Zoidberg::Utils::Output::Scalar->new($error, undef, [ map {
				(ref($_) eq 'ARRAY' and ! grep ref($_), @$_) ? (@$_) : $_
			} @_ ] ) ;
		}
	}
}

sub builtin {
	unshift @_, 'builtin';
	goto \&_shell_cmd;
}

sub command {
	unshift @_, 'system';
	goto \&_shell_cmd;
}

sub _shell_cmd {
	my $type = shift;
	my $self = &_self;
	my $meta = (ref($_[0]) eq 'HASH') ? shift : {};
	$$meta{capture} = defined wantarray;
	$$meta{wantarray} = wantarray;
	local $$self{_settings}{output}{error} = 'mute'
		if delete $$meta{die_silently};
	my $save_error = $$self{error};
	$$self{fg_job} ||= $self;
	my @re = $$self{fg_job}->shell_job( $meta,
		[{context => 'CMD', cmdtype => $type}, @_] );
	$@ = $$self{error};
	$$self{error} = $save_error;
	_return($@, @re);
}

sub readpipe { # TODO handle STDOUT differently, see perlop
	my $self = &_self;
	my @re = $self->shell_string( {capture => 1}, @_ );
	return wantarray ? @re : join('', @re);
}

sub system {
	# quick parser independent way of calling system commands
	# not exported to avoid conflict with perlfunc system
	my $self = &_self;
	open CMD, '|-', @_ or error "Could not open pipe to: $_[0]";
	my @re = (<CMD>);
	close CMD;
	return wantarray ? @re : join('', @re);
	# FIXME where does the error code of cmd go?
}

# ############# #
# Some builtins #
# ############# #

sub alias {
	my $self = &_self;
	my (undef, $hash) = getopt '%', @_;
	$$self{aliases}{$_} = $$hash{$_} for keys %$hash;
	# TODO merge code from Commands here
}

sub unalias {
	my $self = &_self;
	my ($opts, $args) = getopt 'all,a @', @_;
	if ($$opts{all}) { %{$$self{aliases}} = () }
	else {
		for (@$args) {
			error "alias: $_: not found"
				unless delete $$self{aliases}{$_};
		}
	}
	# TODO merge code from Commands here
	# use path2hashref
}

sub set {
	# TODO merge code from Commands here
	# use path2hashref
	my $self = &_self;
	if (ref($_[0]) eq 'HASH') { # perl style, merge hashes
		error 'set: only first argument is used' if $#_;
		%{$self->{settings}} = ( %{$self->{settings}}, %{$_[0]} );
	}
	elsif (ref $_[0]) { error 'set: no support for data type'.ref($_[0]) }
	else {  $self->{settings}{$_}++ for @_ }
}

sub setting {
	# use path2hashref
	my $self = &_self;
	my $key = shift;
	return exists($$self{settings}{$key}) ? $$self{settings}{$key}  : undef;
}

sub source {
	my $self = &_self;
	local $Zoidberg::CURRENT = $self;
	for my $file (@_) {
		my $file = path($file);
		error "source: no such file: $file" unless -f $file;
		debug "going to source: $file";
		# FIXME more intelligent behaviour -- see bash man page
		eval q{package Main; our $SCRIPT = $file; do $file; die $@ if $@ };
		# FIXME wipe Main
		complain if $@;
	}
}

sub job { $Zoidberg::CURRENT->job_by_spec(pop @_) }

package Zoidberg::Shell::JobsArray;

sub TIEARRAY { bless \$Zoidberg::Shell::VERSION, shift } # what else is there to bless ?

sub FETCH { $_[1] ? $Zoidberg::CURRENT->job_by_id($_[1]) : $$Zoidberg::CURRENT{fg_job} }

sub STORE { die "Can't overwrite jobs, try 'push'\n" } # STORE has no meaning for this thing

sub DELETE {
	my $j = $Zoidberg::CURRENT->job_by_id($_[1]);
	return unless $j;
	$j->kill(undef, 'WIPE');
}

sub POP {
	my $last_id;
	$$_{id} > $last_id and $last_id = $$_{id}
		for @{$Zoidberg::CURRENT->{jobs}};
	$_[0]->DELETE($last_id);
}

sub SHIFT { $_[0]->DELETE(1) }

sub PUSH {
	ref($_[1])
		? $Zoidberg::CURRENT->shell_list(   {prepare => 1}, $_[1] )
		: $Zoidberg::CURRENT->shell_string( {prepare => 1}, $_[1] ) ;
}

sub UNSHIFT { die "Can't overwrite jobs, try 'push'\n" }

sub FETCHSIZE { 1 + scalar @{ $Zoidberg::CURRENT->{jobs} } }

sub EXISTS { $Zoidberg::CURRENT->job_by_id($_[1]) }

sub CLEAR { $_->kill(undef, 'WIPE') for @{$Zoidberg::CURRENT->{jobs}} }

sub SPLICE { die "Can't overwrite jobs, try 'delete' or 'push'\n" }

1;

__END__

=head1 NAME

Zoidberg::Shell - A scripting interface to the Zoidberg shell

=head1 SYNOPSIS

        use Zoidberg::Shell;
	my $shell = Zoidberg::Shell->current();
       
	# Order parent shell to 'cd' to /usr
	# If you let your shell do 'cd' that is _NOT_ the same as doing 'chdir'
        $shell->shell(qw{cd /usr});
	
	# Let your parent shell execute a logic list with a pipeline
	$shell->shell([qw{ls -al}], [qw{grep ^d}], 'OR', [qw{echo some error happened}]);
	
	# Create an alias
	$shell->alias({'ls' => 'ls --color=auto'});
	
	# since we use Exporter::Tidy you can also do things like this:
	use Zoidberg::Shell _prefix => 'zoid_', qw/shell alias unalias/;
	zoid_alias({'perlfunc' => 'perldoc -Uf'});

=head1 DESCRIPTION

This module is intended to let perl scripts interface to the Zoidberg shell in an easy way.
The most important usage for this is to write 'source scripts' for the Zoidberg shell which can 
use and change the B<parent> shell environment like /.*sh/ source scripts 
do with /.*sh/ environments.

=head1 EXPORT

Only the subs C<AUTOLOAD> and C<shell> are exported by default.
C<AUTOLOAD> works more or less like the one from F<Shell.pm> by Larry Wall, but it 
includes zoid's builtin functions and commands (also it just prints output to stdout see TODO).

All other methods except C<new> and C<system> can be exported on demand.
Be aware of the fact that methods like C<alias> can mask "plugin defined builtins" 
with the same name, but with an other interface. This can be confusing but the idea is that
methods in this package have a scripting interface, while the like named builtins have
a commandline interface.

The reason the C<system> can't be exported is because it would mask the 
perl function C<system>, also this method is only included so zoid's DispatchTable's can use it.

Also you can import an C<@JOBS> from this module. The ':jobs' tag gives you both C<@JOBS>
and the C<job()> method.

=head1 METHODS

B<Be aware:> All commands are executed in the B<parent> shell environment.

FIXME document the new export tags, document all routines better

=over 4

=item C<new()>

Simple wrapper for the constructor of the Zoidberg class.

=item C<current()>

Returns the current L<Zoidberg> object, which in turn inherits from this package,
or undef when there is no such object.

TODO should also do ipc

=item C<any()>

Uses the current shell if any, else starts a new one.

=item C<system($command, @_)>

Opens a pipe to a system command and returns it's output. Intended for when you want
to call a command B<without> using zoid's parser and job management. This method
has absolutely B<no> intelligence (no expansions, builtins,  etc.), you can only call
external commands with it.

=item C<shell($command, @_)>

If C<$command> is a built-in shell function (possibly defined by a plugin)
or a system binary, it will be run with arguments C<@_>.
The command won't be subject to alias expansion, arguments might be subject
to glob expansion. FIXME double check this

=item C<shell($string)>

Parse and execute C<$string> like it was entered from the commandline.
You should realise that the parsing is dependent on grammars currently in use,
and also on things like aliases etc.

=item C<shell([$command, @_], [..], 'AND', [..])>

Create a logic list and/or pipeline. Available tokens are 'AND', 'OR' and
'EOS' (End Of Statement, ';').

C<shell()> allows for other kinds of pseudo parse trees, these can be considered
as a kind of "expert mode". See L<zoiddevel>(1) for more details.
You might not want to use these without good reason.

=item C<set(..)>

Update settings in parent shell.

	# merge hash with current settings hash
	set( { noglob => 0 } );
	
	# set these bits to true
	set( qw/hide_private_method hide_hidden_files/ );

See L<zoiduser>(1) for a description of the several settings.

=item C<setting($setting)>

Returns the current value for a setting.

=item C<alias(\%aliases)>

Merge C<%aliases> with current alias hash.

	alias( { ls => 'ls ---color=auto' } )

=item C<unalias(@aliases)>

Delete all keys listed in C<@aliases> from the aliases table.

=item C<source($file)>

Run another perl script, possibly also interfacing with zoid.

FIXME more documentation on zoid's source scripts

=item C<job($spec)>

Used to fetch a job object by its spec, for example:

	$shell->job('%-')->kill(); # kill the previous job

=item C<AUTOLOAD>

All calls that get autoloaded are passed directly to the C<shell()> method.
This allows you to use nice syntax like :

	$shell->cd('..');

=back

=head1 JOBS

FIXME splain @JOBS

=head1 TODO

An interface to create background jobs

An interface to get input

Can builtins support both perl data and switches ?

Test script

More syntactic sugar :)

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Utils>,
L<http://github.com/jberger/Zoidberg>

L<Shell>

=cut

