package Zoidberg::Fish::Commands;

our $VERSION = '0.981';

use strict;
#use AutoLoader 'AUTOLOAD';
use Cwd;
use Env qw/@CDPATH @DIRSTACK/;
use base 'Zoidberg::Fish';
use Zoidberg::Utils qw/:default path getopt usage path2hashref/;

# FIXME what to do with commands that use block input ?
#  currently hacked with statements like join(' ', @_)

=head1 NAME

Zoidberg::Fish::Commands - Zoidberg plugin with builtin commands

=head1 SYNOPSIS

This module is a Zoidberg plugin, see Zoidberg::Fish for details.

=head1 DESCRIPTION

This object contains internal/built-in commands
for the Zoidberg shell.

=head2 EXPORT

None by default.

=cut

sub init { 
	$_[0]{dir_hist} = [$ENV{PWD}]; # FIXME try to read log first
	$_[0]{_dir_hist_i} = 0;
}

=head1 COMMANDS

=over 4

=item cd [-v|--verbose] [I<dir>|-|(+|-)I<hist_number>]

=item cd (-l|--list)

Changes the current working directory to I<dir>.
When used with a single dash changes to OLDPWD.

This command uses the environment variable 'CDPATH'. It serves as
a search path when the directory you want to change to isn't found
in the current directory.

This command also uses a directory history.
The '-number' and '+number' switches are used to change directory
to an positive or negative offset in this history.

=cut

sub cd { # TODO [-L|-P] see man 1 bash
	my $self = shift;
	my ($dir, $done, $verbose);
	if (@_ == 1 and $_[0] eq '-') { # cd -
		$dir = $ENV{OLDPWD};
		$verbose++;
	}
	else {
		my ($opts, $args) = getopt 'list,-l verbose,-v +* -* @', @_;
		if (@$args) { # 'normal' cd
			error 'to many arguments' if @$args > 1;
			$dir = $$args[0];
		}

		if (%$opts) {
			$verbose++ if $$opts{verbose};
			if (my ($opt) = grep /^[+-][^\d+lv]$/, @{$$opts{_opts}}) {
				error "unrecognized option '$opt'";
			}
			elsif ($$opts{list}) { # list dirhist
				error 'to many args' if @$args;
				return $$self{shell}->builtin(qw/history --type pwd +1 -2/); # last pwd is current
			}
			elsif (my ($idx) = grep /^[+-]\d+$/, @{$$opts{_opts}}) {
				# cd back/forward in history
				error 'to many args' if @$args;
				$idx -= 1 if $idx < 1; # last pwd is current
				($dir) = $$self{shell}->builtin(qw/history --type pwd/, $idx, $idx);
				$verbose++;
			}
		}
	}

	if ($dir) {
		# due to things like autofs we must *try* every possibility
		# instead of checking '-d'
		$done = chdir path($dir);
		if    ($done)                { message $dir if $verbose }
		elsif ($dir !~ m#^\.{0,2}/#) {
			for (@CDPATH) {
				next unless $done = chdir path("$_/$dir");
				message "$_/$dir"; # verbose
				last;
			}
		}
	}
	else {
		message $ENV{HOME} if $verbose;
		$done = chdir($ENV{HOME});
	}

	unless ($done) {
		error $dir.': Not a directory' unless -d $dir;
		error "Could not change to dir: $dir";
	}
}

#1;

#__END__

=item exec I<cmd>

Execute I<cmd>. This effectively ends the shell session,
process flow will B<NOT> return to the prompt.

=cut

sub exec { # FIXME not completely stable I'm afraid
	my $self = shift;
	$self->{shell}->{round_up} = 0;
	$self->{shell}->shell_string({fork_job => 0}, join(" ", @_));
	# the process should not make it to this line
	$self->{shell}->{round_up} = 1;
	$self->{shell}->exit;
}

=item eval I<cmd>

Eval I<cmd> like a shell command. Main use of this is to
run code stored in variables.

=cut

sub eval {
	my $self = shift;
	$$self{shell}->shell(@_);
}

=item export I<var>=I<value>

Set the environment variable I<var> to I<value>.

TODO explain how export moved varraibles between the perl namespace and the environment

=cut

sub export { # TODO if arg == 1 and not hash then export var from zoid::eval to env :D
	my $self = shift;
	my ($opt, $args, $vals) = getopt 'unexport,n print,p *', @_;
	my $class = $$self{shell}{settings}{perl}{namespace};
	no strict 'refs';
	if ($$opt{unexport}) {
		for (@$args) {
			s/^([\$\@]?)//;
			next unless exists $ENV{$_};
			if ($1 eq '@') { @{$class.'::'.$_} = split ':', delete $ENV{$_} }
			else { ${$class.'::'.$_} = delete $ENV{$_} }
		}
	}
	elsif ($$opt{print}) {
		output [ map {
			my $val = $ENV{$_};
			$val =~ s/'/\\'/g;
			"export $_='$val'";
		} sort keys %ENV ];
	}
	else { # really export
		for (@$args) {
			s/^([\$\@]?)//;
			if ($1 eq '@') { # arrays
				my @env  = defined($$vals{$_})               ? (@{$$vals{$_}})     :
					   defined(*{$class.'::'.$_}{ARRAY}) ? (@{$class.'::'.$_}) : () ;
				$ENV{$_} = join ':', @env if @env;
			}
			else { # scalars
				my $env = defined($$vals{$_})        ? $$vals{$_}        :
		        	       defined(${$class.'::'.$_}) ? ${$class.'::'.$_} : undef ;
				$ENV{$_} = $env if defined $env;
			}
		}
	}
}

=item setenv I<var> I<value>

Like B<export>, but with a slightly different syntax.

=cut

sub setenv {
	shift;
	my $var = shift;
	$ENV{$var} = join ' ', @_;
}

=item unsetenv I<var>

Set I<var> to undefined.

=cut

sub unsetenv {
	my $self = shift;
	delete $ENV{$_} for @_;
}

=item set [+-][abCefnmnuvx]

=item set [+o|-o] I<option>

Set or unset a shell option. Although sometimes confusing
a '+' switch unsets the option, while the '-' switch sets it.

Short options correspond to the following names:

	a  =>  allexport  *
	b  =>  notify
	C  =>  noclobber
	e  =>  errexit    *
	f  =>  noglob
	m  =>  monitor    *
	n  =>  noexec     *
	u  =>  nounset    *
	v  =>  verbose
	x  =>  xtrace     *
	*) Not yet supported by the rest of the shell

See L<zoiduser> for a description what these and other options do.

FIXME takes also hash arguments

=cut

sub set {
	my $self = shift;
	unless (@_) { error 'should print out all shell vars, but we don\'t have these' }
	my ($opts, $keys, $vals) = getopt
	'allexport,a	notify,b	noclobber,C	errexit,e
	noglob,f	monitor,m	noexec,n	nounset,u
	verbose,v	xtrace,x	-o@ +o@  	*', @_;
	# other posix options: ignoreeof, nolog & vi - bash knows a bit more

	my %settings;
	if (%$opts) {
		$settings{$_} = $$opts{$_}
			for grep {$_ !~ /^[+-]/} @{$$opts{_opts}};
		if ($$opts{'-o'}) { $settings{$_} = 1 for @{$$opts{'-o'}} }
		if ($$opts{'+o'}) { $settings{$_} = 0 for @{$$opts{'+o'}} }
	}

	for (@$keys) { $settings{$_} = defined($$vals{$_}) ? delete($$vals{$_}) : 1 }

	for my $opt (keys %settings) {
		if ($opt =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{settings}, $opt);
			error "$path: no such hash in settings" unless $hash;
			$$hash{$key} = $settings{$opt};
		}
		else { $$self{shell}{settings}{$opt} = $settings{$opt} }
	}
}

=item source I<file>

Run the B<perl> script I<file>. This script is B<NOT> the same
as the commandline syntax. Try using L<Zoidberg::Shell> in these
scripts.

=cut

sub source {
	my $self = shift;
	# FIXME more intelligent behaviour -- see bash man page
	$self->{shell}->source(@_);
}

=item alias

=item alias I<name>

=item alias I<name>=I<command>

=item alias I<name> I<command>

Make I<name> an alias to I<command>. Aliases work like macros
in the shell, this means they are substituted before the commnd
code is interpreted and can contain complex statements.

Without I<command> shows the alias defined for I<name> if any;
without arguments lists all aliases that are currently defined.

Aliases are simple substitutions at the start of a command string.
If you want something more intelligent like interpolating arguments
into a string define a builtin command; see L<hash>.

=cut

sub alias { 
	my $self = shift;
	unless (@_) { # FIXME doesn't handle namespaces / sub hashes
		my $ref = $$self{shell}{aliases};
		output [
			map {
				my $al = $$ref{$_};
				$al =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
				"alias $_='$al'",
			} grep {! ref $$ref{$_}} keys %$ref
		];
		return;
	}
	elsif (@_ == 1 and ! ref($_[0]) and $_[0] !~ /^-|=/) {
		my $cmd = shift;
		my $alias;
		if ($cmd =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{aliases}, $cmd);
			error "$path: no such hash in aliases" unless $hash;
			$alias = $$hash{$key};
		}
		elsif (exists $$self{shell}{aliases}{$cmd}) {
			$alias = $$self{shell}{aliases}{$cmd};
	       	}
		else { error $cmd.': no such alias' }
		$alias =~ s/(\\)|'/$1 ? '\\\\' : '\\\''/eg;
		output "alias $cmd='$alias'";
		return;
	}
	
	my (undef, $keys, $val) = getopt '*', @_;
	return unless @$keys;
	my $aliases;
	if (@$keys == (keys %$val)) { $aliases = $val } # bash style
	elsif (! (keys %$val)) { $aliases = {$$keys[0] => join ' ', splice @$keys, 1} }# tcsh style
	else { error 'syntax error' } # mixed style !?

	for my $cmd (keys %$aliases) {
		if ($cmd =~ m#/#) {
			my ($hash, $key, $path) = path2hashref($$self{shell}{aliases}, $cmd);
			error "$path: no such hash in aliases" unless $hash;
			$$hash{$key} = $$aliases{$cmd};
		}
		else { $$self{shell}{aliases}{$cmd} = $$aliases{$cmd} }
	}
}

=item unalias I<name>

Remove an alias definition.

=cut

sub unalias {
	my $self = shift;
	my ($opts, $args) = getopt 'all,a @', @_;
	if ($$opts{all}) { %{$self->{shell}{aliases}} = () }
	else {
		for (@$args) {
			error "alias: $_: not found" unless exists $self->{shell}{aliases}{$_};
			delete $self->{shell}{aliases}{$_};
		}
	}
}

=item hash I<location>

=item hash -r

TODO

Command to manipulate the commands hash and command lookup logic.

=item read [-r] I<var1> I<var2 ..>

Read a line from STDIN, split the line in words 
and assign the words to the named enironment variables.
Remaining words are stored in the last variable.

Unless '-r' is specified the backslash is treated as
an escape char and is it possible to escape the newline char.

=cut

sub read {
	my $self = shift;
	my ($opts, $args) = getopt 'raw,r @';

	my $string = '';
	while (<STDIN>) {
		unless ($$opts{raw}) {
			my $more = 0;
			$_ =~ s/(\\\\)|\\(.)|\\$/
				if ($1) { '\\' }
				elsif (length $2) { $2 }
				else { $more++; '' }
			/eg;
			$string .= $_;
			last unless $more;
		}
		else {
			$string = $_;
			last;
		}
	}
	return unless @$args;

	# TODO honour $IFS here instead of word_gram
	my @words = $$self{shell}{stringparser}->split('word_gram', $string);
	debug "read words: ", \@words;
	if (@words > @$args) {
		@words = @words[0 .. $#$args - 1];
		my $pre = join '\s*', @words;
		$string =~ s/^\s*$pre\s*//;
		push @words, $string;
	}

	$ENV{$_} = shift @words || '' for @$args;
}

=item newgrp

TODO

=cut

sub newgrp { todo }

=item umask

TODO

=cut

sub umask { todo }

=item false

A command that always returns an error without doing anything.

=cut

sub false { error {silent => 1}, 'the "false" builtin' }

=item true

A command that never fails and does absolutely nothing.

=cut

sub true { 1 }

# ######### #
# Dir stack #
# ######### # 

=item dirs

Output the current dir stack.

TODO some options

Note that the dir stack is ont related to the dir history.
It was only implemented because historic implementations have it.

=cut

sub dirs { output @DIRSTACK ? [reverse @DIRSTACK] : $ENV{PWD} }
# FIXME some options - see man bash

=item popd I<dir>

Pops a directory from the dir stack and B<cd>s to that directory.

TODO some options

=cut

sub popd { # FIXME some options - see man bash
	my $self = shift;
	error 'popd: No other dir on stack' unless $#DIRSTACK;
	pop @DIRSTACK;
	my $dir = $#DIRSTACK ? $DIRSTACK[-1] : pop(@DIRSTACK);
	$self->cd($dir);
}

=item pushd I<dir>

Push I<dir> on the dir stack.

TODO some options

=cut

sub pushd { # FIXME some options - see man bash
	my ($self, $dir) = (@_);
	my $pwd = $ENV{PWD};
	$dir ||= $ENV{PWD};
	$self->cd($dir);
	@DIRSTACK = ($pwd) unless scalar @DIRSTACK;
	push @DIRSTACK, $dir;
}

##################

=item pwd

Prints the current PWD.

=cut

sub pwd {
	my $self = shift;
	output $ENV{PWD};
}

=item symbols [-a|--all] [I<class>]

Output a listing of symbols in the specified class.
Class defaults to the current perl namespace, by default
C<Zoidberg::Eval>.

All symbols are prefixed by their sigil ('$', '@', '%', '&'
or '*') where '*' is used for filehandles.

By default sub classes (hashes containing '::')
and special symbols (symbols without letters in their name)
are hidden. Use the --all switch to see these.

=cut

sub symbols {
	no strict 'refs';
	my $self = shift;
	my ($opts, $class) = getopt 'all,a @', @_;
	error 'to many arguments' if @$class > 1;
	$class = shift(@$class)
       		|| $$self{shell}{settings}{perl}{namespace} || 'Zoidberg::Eval';
	my @sym;
	for (keys %{$class.'::'}) {
		unless ($$opts{all}) {
			next if /::/;
			next unless /[a-z]/i;
		}
		push @sym, '$'.$_ if defined ${$class.'::'.$_};
		push @sym, '@'.$_ if *{$class.'::'.$_}{ARRAY};
		push @sym, '%'.$_ if *{$class.'::'.$_}{HASH};
		push @sym, '&'.$_ if *{$class.'::'.$_}{CODE};
		push @sym, '*'.$_ if *{$class.'::'.$_}{IO};
	}
	output [sort @sym];
}

=item reload I<module> [I<module>, ..]

=item reload I<file> [I<file>, ..]

Force (re-)loading of a module file. Typically used for debugging modules,
where you reload the module after each modification to test it interactively.

TODO: recursive switch that scans for 'use' statements

=cut

sub reload {
	shift; # self
	for (@_) {
		my $file = shift;
		if ($file =~ m!/!) { $file = path($file) }
		else {
			$file .= '.pm';
			$file =~ s{::}{/}g;
		}
		$file = $INC{$file} || $file;
		eval "do '$file'";
		error if $@;
	}
}

=item help [I<topic>|command I<command>]

Prints out a help text.

=cut

sub help { # TODO topics from man1 pod files ??
	my $self = shift;
	unless (@_) {
		output << 'EOH';
Help topics:
  about
  command

see also man zoiduser
EOH
		return;
	}

	my $topic = shift;
	if ($topic eq 'about') { output "$Zoidberg::LONG_VERSION\n" }
	elsif ($topic eq 'command') {
		error usage unless scalar @_;
		$self->help_command(@_)
	}
	else { $self->help_command($topic, @_) }
}

sub help_command {
	my ($self, @cmd) = @_;
	my @info = $self->type_command(@cmd);
	if ($info[0] eq 'alias') { output "'$cmd[0]' is an alias\n  > $info[1]" }
	elsif ($info[0] eq 'builtin') {
		output "'$cmd[0]' is a builtin command,";
		if (@info == 1) {
			output "but there is no information available about it.";
		}
		else {
			output "it belongs to the $info[1] plugin.";
			if (@info == 3) { output "\n", Zoidberg::Utils::help($cmd[0], $info[2]) }
			else { output "\nNo other help available" }
		}
	}
	elsif ($info[0] eq 'system') {
		output "'$cmd[0]' seems to be a system command, try\n  > man $cmd[0]";
	}
	elsif ($info[0] eq 'PERL') {
		output "'$cmd[0]' seems to be a perl command, try\n  > perldoc -f $cmd[0]";
	}
	else { todo "Help functionality for context: $info[1]" }
}

=item which [-a|--all|-m|--module] ITEM

Finds ITEM in PATH or INC if the -m or --module option was used.
If the -a or --all option is used all it doesn't stop after the first match.

TODO it should identify aliases

TODO what should happen with contexts other then CMD ?

=cut

sub which {
	my $self = shift;
	my ($opt, $cmd) = getopt 'module,m all,a @', @_;
	my @info = $self->type_command(@$cmd);
	$cmd = shift @$cmd;
	my @dirs;

	if ($$opt{module}) {
		$cmd =~ s#::#/#g;
		$cmd .= '.pm' unless $cmd =~ /\.\w+$/;
		@dirs = @INC;
	}
	else {
		error "$cmd is a, or belongs to a $info[0]"
			unless $info[0] eq 'system';
		# TODO aliases
		@dirs = split ':', $ENV{PATH};
	}

	my @matches;
	for (@dirs) {
		next unless -e "$_/$cmd";
		push @matches, "$_/$cmd";
		last unless $$opt{all};
	}
	if (@matches) { output [@matches] }
	else { error "no $cmd in PATH" }
	return;
}

sub type_command {
	my ($self, @cmd) = @_;
	
	if (
		exists $$self{shell}{aliases}{$cmd[0]}
		and $$self{shell}{aliases}{$cmd[0]} !~ /^$cmd[0]\b/
	) {
		my $alias = $$self{shell}{aliases}{$cmd[0]};
		$alias =~ s/'/\\'/g;
		return 'alias', "alias $cmd[0]='$alias'";
	}

	my $block = $$self{shell}->parse_block({pretend => 1}, [@cmd]);
	my $context = uc $$block[0]{context};
	if (!$context or $context eq 'CMD') {
		return 'system' unless exists $$self{shell}{commands}{$cmd[0]};
		my $tag = $$self{shell}{commands}->tag($cmd[0]);
		return 'builtin' unless $tag;
		my $file = tied( %{$$self{shell}{objects}} )->[1]{$tag}{module};
		return 'builtin', $tag, $file;
	}
	else { return $context }
}

# ############ #
# Job routines #
# ############ #

=item jobs [-l,--list|-p,--pgids] I<job_spec ...>

Lists current jobs.

If job specs are given as arguments only lists those jobs.

The --pgids option only lists the process group ids for the jobs
without additional information.

The --list option gives more verbose output, it adds the process group id
of the job and also shows the stack of commands pending for this job.

This command is not POSIX compliant. It uses '-l' in a more verbose
way then specified by POSIX. If you wat to make sure you have POSIX
compliant verbose output try: C<jobs -l | {! /^\t/}g>.

=cut

sub jobs {
	my $self = shift;
	my ($opts, $args) = getopt 'list,l pgids,p @', @_;
	$args = @$args 
		? [ map {$$self{shell}->job_by_spec($_)} @$args ]
		: $$self{shell}->{jobs} ;
	if ($$opts{pgids}) {
		output [ map $$_{pgid}, @$args ];
	}
	else {
		output $_->status_string(undef, $$opts{list})
			for sort {$$a{id} <=> $$b{id}} @$args;
	}
}

=item bg I<job_spec>

Run the job corresponding to I<jobspec> as an asynchronous background process.

Without argument uses the "current" job.

=cut

sub bg {
	my ($self, $id) = @_;
	my $j = $$self{shell}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting bg: $$j{id} == $j";
	$j->bg;
}

=item fg I<job_spec>

Run the job corresponding to I<jobspec> as a foreground process.

Without argument uses the "current" job.

=cut

sub fg {
	my ($self, $id) = @_;
	my $j = $$self{shell}->job_by_spec($id)
		or error 'No such job'.($id ? ": $id" : '');
	debug "putting fg: $$j{id} == $j";
	$j->fg;
}

=item wait

TODO

=cut

sub wait { todo }

=item kill -l

=item kill [-w | -s I<sigspec>|-n I<signum>|-I<sigspec>] (I<pid>|I<job_spec>)

Sends a signal to a process or a process group.
By default the "TERM" signal is used.

The '-l' option list all possible signals.

The -w or --wipe option is zoidberg specific. It not only kills the job, but also
wipes the list that would be executed after the job ends.

=cut

# from bash-2.05/builtins/kill.def:
# kill [-s sigspec | -n signum | -sigspec] [pid | job]... or kill -l [sigspec]
# Send the processes named by PID (or JOB) the signal SIGSPEC.  If
# SIGSPEC is not present, then SIGTERM is assumed.  An argument of `-l'
# lists the signal names; if arguments follow `-l' they are assumed to
# be signal numbers for which names should be listed.  Kill is a shell
# builtin for two reasons: it allows job IDs to be used instead of
# process IDs, and, if you have reached the limit on processes that
# you can create, you don't have to start a process to kill another one.

# Notice that POSIX specifies another list format then the one bash uses

sub kill {
	my $self = shift;
	my ($opts, $args) = getopt 'wipe,-w list,-l sigspec,-s signum,-n -* @', @_;
	if ($$opts{list}) { # list sigs
		error 'too many options' if @{$$opts{_opts}} > 1;
		my %sh = %{ $$self{shell}{_sighash} };
		my @k = @$args ? (grep exists $sh{$_}, @$args) : (keys %sh);
		output [ map {sprintf '%2i) %s', $_, $sh{$_}} sort {$a <=> $b} @k ];
		return;
	}
	else { error 'to few arguments' unless @$args }

	my $sig = $$opts{signum} || '15'; # sigterm, the default
	if ($$opts{_opts}) {
		for ($$opts{signum}, grep s/^-//, @$args) {
			next unless $_;
			my $sig = $$self{shell}->sig_by_spec($_);
			error $_.': no such signal' unless defined $sig;
		}
	}

	for (@$args) {
		if (/^\%/) {
			my $j = $$self{shell}->job_by_spec($_)
				or error "$_: no such job";
			$j->kill($sig, $$opts{wipe});
		}
		else { CORE::kill($sig, $_) }
	}
}

=item disown

TODO

=cut

sub disown { # dissociate job ... remove from @jobs, nohup
	todo 'see bash manpage for implementaion details';

	# is disowning the same as deamonizing the process ?
	# if it is, see man perlipc for example code

	# does this suggest we could also have a 'own' to hijack processes ?
	# all your pty are belong:0
}

=back

=head2 Job specs

TODO tell bout job specs

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>
R.L. Zwart, E<lt>rlzwart@cpan.orgE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Zoidberg>, L<Zoidberg::Fish>

=cut

1;

