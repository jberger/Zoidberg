package Zoidberg;

our $VERSION = '0.97';
our $LONG_VERSION = "Zoidberg $VERSION

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

http://github.com/jberger/Zoidberg";

use strict;
use vars qw/$AUTOLOAD/;
#use warnings;
#no warnings 'uninitialized'; # yes, undefined == '' == 0
no warnings; # I am leaving this, because I don't totally understand how warnings propagate through -- Joel

require Cwd;
require File::Glob;
use File::ShareDir qw/dist_dir/;
use File::Copy qw/copy/;
use File::Spec::Functions qw/catfile/;

require Zoidberg::Contractor;
require Zoidberg::Shell;
require Zoidberg::PluginHash;
require Zoidberg::StringParser;

use Zoidberg::DispatchTable;
use Zoidberg::Utils
	qw/:error :output :fs read_data_file merge_hash regex_glob getopt/;

our @ISA = qw/Zoidberg::Contractor Zoidberg::Shell/;

=head1 NAME

Zoidberg - A modular perl shell

=head1 SYNOPSIS

You should use the B<zoid> system command to start the Zoidberg shell.
To embed the Zoidberg shell in another perl program use the L<Zoidberg::Shell>
module.

=head1 DESCRIPTION

I<This page contains devel documentation, if you're looking for user documentation start with the zoid(1) and zoiduser(1) man pages.>

This module contains the core dispatch and event logic of the Zoidberg shell.
Also it is used as a 'main object' so other objects can find each other here;
all other objects are nested below this object.
Also it contains some parser code.

This object inherits from both L<Zoidberg::Contractor>
and L<Zoidberg::Shell>.

=head1 METHODS

=over 4

=cut

our %OBJECTS; # used to store refs to ALL Zoidberg objects in a process
our $CURRENT; # current Zoidberg object

our $_base_dir; # relative path for some settings
our @_parser_settings = qw/
	split_script split_words
	parse_env parse_fd parse_aliases parse_def_contexts
	expand_comm expand_param expand_path
/;

our %_settings = ( # default settings
	output => { error => 'red', debug => 'yellow' },
	clothes => {
		keys => [qw/settings commands aliases events error/],
		subs => [qw/shell alias unalias setting set source mode plug unplug/],
	},
	perl => {
		keywords => [qw/
			if unless for foreach while until 
			print
			push shift unshift pop splice
			delete
			do eval
			tie untie
			my our use no sub package
			import bless
		/],
		namespace => 'Zoidberg::Eval',
		opts => 'Z',
	},
	hide_private_method => 1,
	hide_hidden_files => 1,
	naked_zoid => 0,
	( map {($_ => 1)} @_parser_settings ),
	##Insert defaults here##
	rcfiles => [
		( $ENV{PAR_TEMP} ? "$ENV{PAR_TEMP}/inc/etc/zoidrc" : '/etc/zoidrc' ),
 		"$ENV{HOME}/.zoidrc",
		"$ENV{HOME}/.zoid/zoidrc", 
	],
	data_dirs => [
		"$ENV{HOME}/.zoid",
		( $ENV{PAR_TEMP} ? "$ENV{PAR_TEMP}/inc/share" : ( qw# /usr/local/share/zoid /usr/share/zoid # ) ),
		dist_dir('Zoidberg'),
	],
);
our %_grammars = ( # default grammar
	_base_gram => {
	        esc => '\\',
	        quotes => {
	                '"' => '"',
	                "'" => "'",
			'`' => '`',
	        },
	        nests => {
	                '{' => '}',
			'(' => ')',
	        },
	},
	script_gram => {
	        tokens => [
			[ ';',	'EOS'  ],
			[ "\n",	'EOL'  ],
	                [ '&&',	'AND'  ],
			[ '||',	'OR'   ],
	                [ '|',	'_CUT' ],
			[ qr/(?<![<>])&/ , 'EOS_BG' ],
			[ '==>', 'XFW' ],
			[ '<==', 'XBW' ],
	        ],
	},
	word_gram => qr/\s/,
	redirect_gram => {
		s_esc  => qr/[\\\-\=]/,
		tokens => [
			[ qr/<\S+>/, '_SELF' ],
			[ '>&', 'DUP_OUT'  ],
			[ '>|', 'CLOB_OUT' ],
			[ '>!', 'CLOB_OUT' ],
			[ '>>', 'APP_OUT'  ],
			[ '<&', 'DUP_IN'   ],
			[ '<<', 'ERROR'    ],
			[ '<>', 'RW'       ],
			[ '>',  'OUT'      ],
			[ '<',  'IN'       ],
		],
	},
	dezoid_gram => {
		tokens => [
			[ qr/->/, 'ARR' ], # ARRow
			[ qr/[\$\@][A-Za-z_][\w\-]*(?<!\-)/, '_SELF' ], # env var
		],
		quotes => { "'" => "'" }, # interpolate also between '"'
		nests => {},
	},
	expand_comm_gram => {
		tokens => {
			'$(' => {
				token  => 'COMM',
				tokens => {')' => '_CUT'},
			},
			'`'  => {
				token  => 'COMM',
				tokens => {'`' => '_CUT'},
			}
		},
	},
#	expand_braces_gram => {
#		tokens => {
#			'{' => {
#				token => 'BRACE',
#				tokens => { '}' => '_CUT' },
#			},
#		},
#	},
);

=item C<new(\%attr)>

Initialize secondary objects and sets config.
C<%attr> contains non-default attributes and is used to set runtime settings.

You probably don't want to use this to construct a new Zoidberg shell object,
better use L<Zoidberg::Shell>.

=cut

sub new { # FIXME maybe rename this to init ?
	my $class = shift;
	my $self = @_ ? { @_ } : {};
	$$self{$_} ||= {} for qw/settings commands aliases events objects/;
	$$self{no_words} ||= [];
	push @{$$self{no_words}}, qw/PERL SUBZ/; # parser stuff
	$$self{round_up}++;
	$$self{topic} ||= '';

	bless($self, $class);

	$OBJECTS{"$self"} = $self;
	$CURRENT = $self unless ref( $CURRENT ) eq $class; # could be autovivicated
	$self->{shell} = $self; # for Contractor

	## settings
	$$self{_settings} = merge_hash(\%_settings, $$self{settings});
	$$self{_settings}{data_dirs}
		|| error 'You should at least set a config value for \'data_dirs\'';

	my %set;
	tie %set, 'Zoidberg::SettingsHash', $$self{_settings}, $self;
	$$self{settings} = \%set;

	## commands
	$$self{commands} = Zoidberg::DispatchTable->new(
		$self, {
			exit	 => '->exit',
			plug	 => '->plug',
			unplug	 => '->unplug',
			mode	 => '->mode',
			readline => "->stdin('zoid-$VERSION\$ ')",
			readmore => "->stdin('> ')",
			builtin  => '->builtin',
			command	 => '->command',
			( %{$$self{commands}} )
		}
	);

	## events
	$$self{events} = Zoidberg::DispatchTable->new($self, $$self{events});
	$$self{events}{envupdate} = sub {
		my $pwd = Cwd::cwd();
		return if $pwd eq $ENV{PWD};
		@ENV{qw/OLDPWD PWD/} = ($ENV{PWD}, $pwd);
		$self->broadcast('newpwd');
		$self->builtin('log', $pwd, 'pwd') if $$self{settings}{interactive};
	};

	## parser
	$$self{parser} = Zoidberg::DispatchTable->new($self, $$self{parser});

	## stringparser 
	$$self{grammars} ||= \%_grammars;
	$$self{stringparser} = Zoidberg::StringParser->new(
		$$self{grammars}{_base_gram}, $$self{grammars},
	       	{allow_broken => 1, no_esc_rm => 1} );

	## initialize contractor
	$self->shell_init;

	## plugins
	my %objects;
	tie %objects, 'Zoidberg::PluginHash', $self;
	$self->{objects} = \%objects;

	# autoloading of contexts after plugin loading
	# because of bootstrapping issues
	$$self{parser}{_AUTOLOAD} = sub {
		my $c = shift;
		debug "trying to autoload $c";
		if ($c =~ /::/) {
			$c =~ m#(.*?)(::|->)$#;
			my ($class, $type) = ($1, $2);
			debug "loading class $class";
			$$self{parser}{$c} = {};
			$$self{parser}{$c}{handler} = sub {
				my (undef, $sub, @args) = @{ shift() };
				unshift @args, $class if $type eq '->';
				no strict 'refs';
				$sub = $class.'::'.$sub;
				$sub->(@args);
			};
			$$self{parser}{$c}{intel} = sub {
				my $block = shift;
				return undef if @$block > 2;
				no strict 'refs';
				my @p = grep m/^$$block[1]/,
					grep defined *{$class.'::'.$_}{CODE}, keys %{$class.'::'};
				push @p, grep m/^$$block[1]/, keys %{$$self{aliases}{'mode_'.$c}}
					if exists $$self{aliases}{'mode_'.$c};
				$$block[0]{poss} = \@p;
				return $block;
			};
		}
		else { eval { $self->plug($c) } }
		debug 'did you know 5.6.2 sucks ?' if $] < 5.008; # don't ask ... i suspect another vivication bug
		return exists($$self{parser}{$c}) ? $$self{parser}{$c} : undef ;
	};

	## let's load the rcfiles
	$$self{events}{loadrc} = sub {
		#check for existant rcfiles in the known locations
		my @rcfiles = grep {-f $_} @{$$self{_settings}{rcfiles}};
		#if no zoidrc file is found, create one from the template in the dist_dir
		unless (@rcfiles) {
			my $rc_template = catfile(dist_dir('Zoidberg'), "zoidrc.example");
			my $new_rc = catfile($ENV{HOME}, ".zoidrc");
			warn "### No zoidrc file was found. A new zoidrc file will be created for you at $new_rc. If you really intend to use without a zoidrc file, simply create an empty zoidrc file in that location or at /etc/zoidrc\n\n";
			if( copy( $rc_template, $new_rc) ) {
				push @rcfiles, $new_rc;
			} else {
				warn "### Could not copy $rc_template to $new_rc\n\n";
			}
			
		}
		$self->source(@rcfiles);
	};
	$self->broadcast('loadrc');

	$self->broadcast('envupdate'); # set/log pwd and maybe init other env stuff

	return $self;
}

sub import { bug "You should use Zoidberg::Shell to import from" if @_ > 1 }

# hooks overloading Contracter # FIXME these are not used !?
*pre_job = \&parse_block;
*post_job = \&broadcast;

# ############ #
# Main routine #
# ############ #

=item C<main_loop()>

Spans interactive shell reading from a secondary ReadLine object or from STDIN.

To quit this loop the routine C<exit()> of this package should be called.
Most common way to do this is pressing ^D.

=cut

sub main_loop {
	my $self = shift;

	$$self{_continue} = 1;
	while ($$self{_continue}) {
		$self->reap_jobs();
		$self->broadcast('prompt');
		my ($cmd) = $self->builtin('readline');
		if ($@) {
			complain "\nInput routine died. (You can interrupt zoid NOW)";
			local $SIG{INT} = 'DEFAULT';
			sleep 1; # infinite loop protection
		}
		else {
			$self->reap_jobs();

			unless (defined $cmd || $$self{_settings}{ignoreeof}) {
				debug 'readline returned undef .. exiting';
				$self->exit();
			}
			else { $$self{_warned_bout_jobs} = 0 }

			last unless $$self{_continue};

			$self->shell_string({interactive => 1}, $cmd) if length $cmd;
		}
	}
}

# ############ #
# Parser stuff #
# ############ #

sub shell_string {
	my ($self, $meta, $string) = @_;
	($meta, $string) = ({}, $meta) unless ref($meta) eq 'HASH';
	local $CURRENT = $self;

	PARSE_STRING:
	my @list = $$self{_settings}{split_script}
       		? ($$self{stringparser}->split('script_gram', $string)) : ($string) ;
	my $b = $$self{stringparser}{broken} ? 1
		: (@list and ! ref $list[-1] and $list[-1] !~ /^EO/) ? 2 : 0 ;
	if ($b and ! $$self{_settings}{interactive}) { # FIXME should be STDIN on non interactive
		error qq#Operator at end of input# if $b == 2;
		my $gram = $$self{stringparser}{broken}[1];
		error qq#Unmatched $$gram{_open}[1] at end of input: $$gram{_open}[0]#;
	}
	elsif ($b) {
		($string) = $self->builtin('readmore');
		debug "\n\ngot $string\n\n\n";
		if ($@) {
			complain "\nInput routine died.\n$@";
			return;
		}
		goto PARSE_STRING;
	}

	if ($$meta{interactive}) {
		$self->broadcast('cmd', $string);
		$$self{previous_cmd} = $string;
		print STDERR $string if $$self{_settings}{verbose}; # posix spec
	}

	debug 'block list: ', \@list;
	$$self{fg_job} ||= $self;
	$$self{fg_job}->shell_list($meta, @list); # calling a contractor
}

sub prepare_block {
	my ($self, $block) = @_;
	my $t = ref $block;
	if ($t eq 'SCALAR') { $block = [{env => {pwd => $ENV{PWD}}}, $$block] }
	elsif ($t eq 'ARRAY') {
		if (ref($$block[0]) eq 'HASH') { $$block[0]{env}{pwd} ||= $ENV{PWD} }
		else { unshift @$block, {env => {pwd => $ENV{PWD}}} }
	}
	else {
		bug $t ? "prepare_block can't handle type $t"
		       : "block ain't a ref !??" ;
	}
	return $block;
}

sub parse_block { # call as late as possible before execution
 	# FIXME can this be more optimised for builtin() call ?
	my $self = shift;
	my $meta = (ref($_[0]) eq 'HASH') ? shift : {};
	my $block = shift;

	# check settings
	$$meta{$_} = $$self{_settings}{$_} for grep {! defined $$meta{$_}} @_parser_settings;
	# FIXME mode settings, uc || lc ?
	
	# decipher block
	PARSE_BLOCK:
	my @words;
	my $t = ref $block;
	if (!$t or $t eq 'SCALAR') {
		($meta, @words) = @{ $self->parse_env([$meta, $t ? $$block : $block]) };
		++$$meta{no_mode} and (length $words[0] or shift @words) if @words && $words[0] =~ s/^\!\s*//;
	}
	elsif ($t eq 'ARRAY') {
		$meta = { %$meta, %{shift @$block} } if ref($$block[0]) eq 'HASH';
		unless (@$block > 1 or $$meta{plain_words}) {
				debug "block aint a word block";
				$block = shift @$block;
				goto PARSE_BLOCK;
		}
		@words = @$block;
		++$$meta{no_mode} and shift @words if @words && $words[0] eq '!';
	}
	elsif ($t eq 'CODE') { return [{context => 'PERL', %$meta}, $block] }
	else { bug "parse tree contains $t reference" }

	# do aliases
	debug 'meta: ', $meta; # , 'words: ', [[@words]];
	if (@words and ! $$meta{pretend} and $$meta{parse_aliases}) {
		my @blocks = $self->parse_aliases($meta, @words);
		if (@blocks > 1) { return @blocks } # probably an alias contained pipe or logic operator
		elsif (! @blocks) { return undef }
		else {
			($meta, @words) = @{ shift(@blocks) };
		}
	}
	# post alias stuff
	$$meta{zoidcmd} = join ' ', @words; # unix haters guide pdf page 60 
	#FIXME how does this hadle escaped whitespacec ?
	$$meta{no_mode}++ if $words[0] eq 'mode'; # explicitly after alias expansion .. ! is before alias expansion

	# check custom filters
	for my $sub ($$self{parser}->stack('filter')) {
		my $r = $sub->([$meta, @words]);
		($meta, @words) = @$r if $r; # skip on undef
	}
	return undef unless $$meta{context} or @words;

	$$meta{context} = 'SUBZ' if $$meta{zoidcmd} =~ /^\s*\(.*\)\s*$/s; # check for subshell

	# check builtin contexts/filters
	unless ($$meta{context} or ! $$meta{parse_def_contexts}) {
		debug 'trying builtin contexts';
		my $perl_regexp = join '|', @{$self->{_settings}{perl}{keywords}};
		if (
			$$meta{zoidcmd} =~ s/^\s*(\w*){(.*)}(\w*)\s*$/$2/s or $$meta{pretend} and
			$$meta{zoidcmd} =~ s/^\s*(\w*){(.*)$/$2/s
		) { # all kinds of blocks with { ... }
			unless (length $1) { @$meta{qw/context opts/} = ('PERL', $3 || '') }
			elsif (grep {$_ eq $1} qw/s m tr y/) {
				$$meta{zoidcmd} = $1.'{'.$$meta{zoidcmd}.'}'.$3; # always the exceptions
				@$meta{qw/context opts/} = ('PERL', ($1 eq 'm') ? 'g' : 'p')
			}
			else {
				@$meta{qw/context opts/} = (uc($1), $3 || '');
				@words = $$self{stringparser}->split('word_gram', $$meta{zoidcmd});
			}
		}
		elsif ($$meta{zoidcmd} =~ s/^\s*(\w+):\s+//) { # little bit o psh2 compat
			$$meta{context} = uc $1;
			shift @words;
		}
		elsif (@words == 1 and $words[0] =~ /^%/) { unshift @words, 'fg' } # and another exception
		elsif ($words[0] =~ /^\s*(->|[\$\@\%\&\*\xA3]\S|\w+::|\w+[\(\{]|($perl_regexp)\b)/s) {
			$$meta{context} = 'PERL';
		}
	}

	$$meta{env}{ZOIDCMD} = $$meta{zoidcmd}; # unix haters guide, pdf page 60
	if ($$self{_settings}{mode} and ! $$meta{no_mode}) {
		my $m = $$self{_settings}{mode};
		$$meta{context} ||= ($m =~ /::/) ? $m : uc($m);
	}

	return [$meta, @words] if $$meta{pretend} and @words == 1;

	# check custom contexts
	unless ($$meta{context}) {
		debug 'trying custom contexts';
		for my $pair ($$self{parser}->stack('word_list', 'TAGS')) {
			my $r = $$pair[0]->([$meta, @words]);
			unless ($r) { next }
			elsif (ref $r) { ($meta , @words) = @$r }
			else { $$meta{context} = length($r) > 1 ? $r : $$pair[1] }
			last if $$meta{context};
		}
	}

	# use default builtin context
	unless ($$meta{context} or ! $$meta{parse_def_contexts}) {
		debug 'using default context';
		$$meta{context} = 'CMD';
	}

	if (
		exists $$self{parser}{$$meta{context}} and
		exists $$self{parser}{$$meta{context}}{parser}
	) { # custom parser
		($meta, @words) = @{ $$self{parser}{$$meta{context}}{parser}->([$meta, @words]) };
	}
	elsif (grep {$$meta{context} eq $_} @{$$self{no_words}}) { # no words
		@words = $$meta{pretend} 
			? $$self{stringparser}->split('word_gram', $$meta{zoidcmd})
			: ( $$meta{zoidcmd} ) ;
		$$meta{fork_job} = 1 if $$meta{context} eq 'SUBZ';
		($meta, @words) = @{ $self->parse_perl([$meta, @words]) }
			if ! $$meta{pretend} and $$meta{context} eq 'PERL';
	}
	elsif (@words and ! $$meta{pretend}) { # expand and set topic
		($meta, @words) = @{ $self->parse_words([$meta, @words]) } unless $$meta{plain_words};
		$$self{topic} =
# FIXME			exists($$meta{fd}{0})               ? $$meta{fd}{0}[0] :
			(@words > 1 and $words[-1] !~ /^-/) ? $words[-1]       : $$self{topic};
		$$meta{fork_job} = 1 if $$meta{context} eq 'CMD' and
			$$meta{cmdtype} ne 'builtin' and ! exists $$self{commands}{$words[0]};
	}
	return [$meta, @words];
}

our %_redir_ops = (
	IN => '<', OUT => '>',
       	CLOB_OUT => '>!', APP_OUT => '>>',
       	RW => '+<', DUP_OUT => '>&', DUP_IN => '<&'
);

sub parse_env {
	my ($self, $block) = @_;
	my ($meta, @words) = @$block;

	if (@words > 1 or ! $$meta{split_words}) {
		$$meta{string} = join ' ', @words;
	}
	else {
		$$meta{string} = $words[0];
		@words = $$self{stringparser}->split('word_gram', $words[0])
	}
	# FIXME parse word_gram and redir_gram at same time

	# parse environment
	if ($$meta{parse_env}) {
		my $_env = delete $$meta{env}; # PWD and SHELL
		while ($words[0] =~ /^(\w[\w\-]*)=(.*)/s) {
			$$meta{compl} = shift @words;
			$$meta{env}{$1} = $2
		}
		if (! @words and $$meta{env}) { # special case
			@words = ('export', map $_.'='.$$meta{env}{$_}, keys %{$$meta{env}});
			delete $$meta{env}; # duplicate would make var local
		}
		elsif ($$meta{env}) {
			delete $$meta{compl}; # @words > 0
			for (keys %{$$meta{env}}) {
				my (undef, @w) = @{ $self->parse_words([$meta, $$meta{env}{$_}]) };
				$$meta{env}{$_} = join ':', @w;
			}
		}
		for (keys %$_env) {
			$$meta{env}{$_} = $$_env{$_} unless defined $$meta{env}{$_};
		}
	}

	# parse redirections
	return [$meta, @words] unless $$meta{parse_fd};
	my @s_words = map [ $$self{stringparser}->split('redirect_gram', $_) ], @words;
	return [$meta, @words] if ! grep {! ref $_} map @$_, @s_words;
	$$meta{fd} ||= [];
	my @re;

	PARSE_REDIR_S_WORD:
	my @parts = @{shift @s_words};
	my $last = $#parts; # length of @parts changes later on
	for (0 .. $#parts) {
		next unless defined $parts[$_] and ! ref $parts[$_];
		my $op = delete $parts[$_];
		if ($op =~ /[^A-Z_]/) { # _SELF escape for "<fh>"
			$parts[$_] = \$op;
			next;
		}
		elsif ($op eq 'ERROR') { 
			error 'redirection operation not supported'
				unless $$meta{pretend};
		}

		my ($n, $word);
		if ($_ > 0 and ref $parts[$_-1]) { # find file descriptor number
			if (${$parts[$_-1]} =~ /^\d+$/) { $n = ${delete $parts[$_-1]} }
			else {
				${$parts[$_-1]} =~ s/(\\\\)|(\\\d+)$|(\d+)$/$1 || $2/eg;
				$n = $3;
			}
		}

		if ($_ < $#parts and ref $parts[$_+1]) { # find argument
			$word = ${ delete $parts[$_+1] };
			$$meta{compl} = $word if $_+1 == $last and ! @s_words; # complete last word
		}
		elsif (@s_words and ref $s_words[0][0]) {
			$word = ${ delete $s_words[0][0] };
			$$meta{compl} = $word if @s_words == 1 and ! @{$s_words[0]};
		}
		else {
			error 'redirection needs argument'
				unless $op =~ /^DUP/ or $$meta{pretend};
			$$meta{compl} = '';
		}

		unless ($$meta{pretend}) {
			$n ||= ($op =~ /OUT$/) ? 1 : 0;
			my (undef, @w) = @{ $self->parse_words([$meta, $word]) };
			if (@w == 1) { push @{$$meta{fd}}, $n.$_redir_ops{$op}.$w[0] }
			elsif (@w > 1) { error 'redirection argument expands to multiple words' }
			else { error 'redirection needs argument' } # @w < 1
		}
	}
	push @re, map $$_, @parts;
	goto PARSE_REDIR_S_WORD if @s_words;

	return [$meta, @re];
}

sub parse_aliases { # recursive sub (aliases are 3 way recursive, 2 ways are in this sub)
	my ($self, $meta, @words) = @_;
	my $aliases = ($$self{_settings}{mode} && ! $$meta{no_mode})
		? $$self{aliases}{'mode_'.$$self{_settings}{mode}}
		: $$self{aliases};
	return [$meta, @words] unless ref $aliases and exists $$aliases{$words[0]};
	$$meta{alias_stack} ||= [];
	return [$meta, @words] if grep {$_ eq $words[0]} @{$$meta{alias_stack}};
	push @{$$meta{alias_stack}}, $words[0];

	my $string = $$aliases{$words[0]};
	debug "$words[0] is aliased to: $string";
	shift @words;

=cut

# saving code for later usage in pipelines
# this is not the right place for it

	{ # variable substitution in the macro
		local @_ = @words;
		my $n = ( $string =~ s# (?<!\\) (?: \$_\[(\d+)\] | \@_(\[.*?\])? ) #
			if ($1) { $words[$1] }
			elsif ($2) { eval "join ' ', \@_[$2]" }
			else { join ' ', @words }
		#xge );
		@words = () if $n;
	}

=cut

	my @as = @{$$meta{alias_stack}}; # force copy
	my @l = map {
		ref($_) ? [ 
			{ alias_stack => [@as] },
			$$self{stringparser}->split('word_gram', $$_)
		] : $_
	} $$meta{split_script} ? ($$self{stringparser}->split('script_gram', $string)) : ($string);

	if ( my ($firstref) = grep ref($_), @l ) {
		$$firstref[0]  = $meta; # re-insert %meta
		++$$meta{no_mode} and (length $$firstref[1] or delete $$firstref[1])
	       		if @$firstref > 1 and $$firstref[1] =~ s/^\!\s*//; # check mode
	}

	if ($string =~ /\s$/) { # recurs for 2nd word - see posix spec
		my @l1 = $self->parse_aliases({}, @words); # recurs
		push @{$l[-1]}, splice(@{ shift(@l1) }, 1) if ref $l[-1] and ref $l1[0];
		push @l, @l1;
	}
	elsif (@l == 1) { return $self->parse_aliases(@{$l[0]}, @words) } # recurs
	else {
		if (ref $l[-1]) { push @{$l[-1]}, @words }
		else { push @l, \@words }
	}

	return @l;
}

sub parse_words { # expand words etc.
	my ($self, $block) = @_;

	# custom stack
	for ($$self{parser}->stack('word_expansion')) {
		my $re = $_->($block);
		$block = $re if $re;
	}

	# default expansions
	# expand_comm resets zoidcmd, all other stuff is left for appliction level re-parsing
	@$block = $self->$_(@$block)
		for grep $$block[0]{$_}, qw/expand_param expand_comm expand_path/;

	# remove quote
	my ($meta, @words) = @$block;
	for (@words) {
		if (/^([\/\w]+=)?(['"])(.*)\2$/s) {
		       	# quote removal and escape removal within quotes
			$_ = $1.$3;
			if ($2 eq '\'') { $_ =~ s/\\([\\'])/$1/ge }
			else            { $_ =~ s/\\(.)/$1/ge     }
		}
		# FIXME also do escape removal here
		# is now done by File::Glob
	}

	return [$meta, @words];
}

=cut

# so far no luck of getting this to work - maybe combine intgrate
#  this with stringparser some how :S

our $_IFS = [undef, qr/\s+/, qr/\s+/];
sub _split_on_IFS { # bloody heavy routine for such a simple parsing rule
	my $self = shift;
	unless ($ENV{IFS} eq $$_IFS[0]) {
		debug "generating new IFS regexes";
		if (! defined $ENV{IFS}) { $_IFS = [undef, qr/\s+/, qr/\s+/] }
		elsif ($ENV{IFS} eq '')  { $_IFS = ['']                      }
		else {
			my $ifs_white = join '', ($ENV{IFS} =~ m/(\s)/g);
			my $ifs_char  = join '', ($ENV{IFS} =~ m/(\S)/g);
			$_IFS = [ $ENV{IFS}, qr/[$ifs_white]+/,
				qr/[$ifs_white]*[$ifs_char][$ifs_white]*|[$ifs_white]+/ ];
		}
		debug "IFS = ['$ENV{IFS}', $$_IFS[1], $$_IFS[2]]";
	}
		debug "IFS = ['$ENV{IFS}', $$_IFS[1], $$_IFS[2]]";
	return @_ if defined $$_IFS[0] and $$_IFS[0] eq '';
	return map {
		$_ =~ s/(\\\\)|^$$_IFS[1]|(?<!\\)$$_IFS[1]$/$1?$1:''/ge;
		$$self{stringparser}->split($$_IFS[2], $_)
	} @_;
}

=cut

=cut

sub expand_braces {
	my ($self, $meta, @words) = @_;
	my @re;
	for (@words) {
		my @parts = $$self{stringparser}->split('expand_braces_gram', $_);
		error $$self{stringparser}{broken} if $$self{stringparser}{broken};
		# FIXME let stringparser do the error throwing ?
		unless (@parts > 1) {
			push @re, $_;
			next;
		}
		for (0 .. $#parts) {
			if ($parts[$_] eq 'BRACE') {
				my $braced = delete $parts[$_+1];

			}
			elsif (ref $parts[$_]) { $parts[$_] = ${$parts[$_]} }
		}
		push @re, join '', map {ref($_) ? (@$_) : $_} @parts;
	}
	return ($meta, @re);
}

=cut

sub expand_param {
	# make sure $() and @() remain untouched ... `` are considered quotes
	no strict 'refs';
	my ($self, $meta, @words) = @_;
	my ($e);
	
	my $class = $$self{_settings}{perl}{namespace};
	@words = map { # substitute vars
		if (/^([\/\w]+=)?'.*'$/s) { $_ }# skip quoted words
		else {
			my $old = $_;
			s{(?<!\\)\$\?}{ ref($$self{error}) ? $$self{error}{exit_status} : $$self{error} ? 1 : 0 }ge;
			s{ (?<!\\) \$ (?: \{ (.*?) \} | ([\w-]+) ) (?: \[(-?\d+)\] )? }{
				my ($w, $i) = ($1 || $2, $3);
				$e ||= "no advanced expansion for \$\{$w\}" if $w =~ /[^\w-]/;
				if ($w eq '_') { $w = $$self{topic} }
				elsif (exists $$meta{env}{$w} or exists $ENV{$w}) {
					$w = exists( $$meta{env}{$w} ) ? $$meta{env}{$w} : $ENV{$w} ;
					$w = $i ? (split /:/, $w)[$i] : $w;
				}
				elsif ($i ? defined(*{$class.'::'.$w}{ARRAY}) : defined(*{$class.'::'.$w}{SCALAR})) {
					$w = $i ? ${$class.'::'.$w}[$i] : ${$class.'::'.$w};
				}
				else { $w = '' }
				$w =~ s/\\/\\\\/g; # literal backslashes
				$w;
			}exg;
			if ($_ eq $old or $_ =~ /^".*"$/) { $_ }
			else { $$self{stringparser}->split('word_gram', $_) }
			# TODO honour IFS here -- POSIX tells us so
		}
	}

	@words = map { # substitute arrays
		if (m/^ \@ (?: \{ (.*?) \} | ([\w-]+) ) $/x) {
			my $w = $1 || $2;
			$e ||= "no advanced expansion for \@\{$w\}" if $w =~ /[^\w-]/;
			$e ||= '@_ is reserved for future syntax usage' if $2 eq '_';
			if (exists $$meta{env}{$w} or exists $ENV{$w}) {
				$w = (exists $$meta{env}{$w}) ? $$meta{env}{$w}  : $ENV{$w};
				map {s/\\/\\\\/g; $_} split /:/, $w;
			}
			elsif (defined *{$class.'::'.$w}{ARRAY}) {
				map {s/\\/\\\\/g; $_} @{$class.'::'.$w};
			}
			else { () }
		}
		else { $_ }
	} @words;
	error $e if $e; # "Attempt to free unreferenced scalar" when dying inside the map !?
	return ($meta, @words);
}

sub expand_comm {
	my ($self, $meta, @words) = @_;
	my @re;
	my $m = {capture => 1, env => $$meta{env}};
	for (@words) {
		if (/^([\/\w]+=)?'.*'$/s) {
			push @re, $_;
		}
		elsif (/^\@\((.*?)\)$/s) {
			debug "\@() subz: $1";
			push @re, $self->shell($m, $1); # list context
		}
		else {
			my $quote = $1 if s/^(")(.*)\1$/$2/s;
			my @parts = $$self{stringparser}->split('expand_comm_gram', $_);
			error $$self{stringparser}{broken} if $$self{stringparser}{broken};
			# FIXME let stringparser do the error throwing ?
			unless (@parts > 1) {
				push @re, $quote ? $quote.$_.$quote : $_;
				next;
			}
			for (0 .. $#parts) {
				if ($parts[$_] eq 'COMM') {
					debug '$() subz: '.$parts[$_+1];
					$parts[$_] = $self->shell($m, ${delete $parts[$_+1]}); # scalar context
					if ($_ < $#parts-1 and ${$parts[$_+2]} =~ s/^\[(\d*)\]//) {
						$parts[$_] = $parts[$_][$1];
						chomp $parts[$_];
					}
					else { $parts[$_] = "$parts[$_]" } # just to be sure bout overload
				}
				elsif (ref $parts[$_]) { $parts[$_] = ${$parts[$_]} }
			}
			my $word = join '', @parts; # map {ref($_) ? (@$_) : $_} @parts;
			if ($quote) { push @re, $quote.$word.$quote }
			else { push @re, $$self{stringparser}->split('word_gram', $word) }
			# TODO honour IFS here - POSIX says so
		}
	}
	$$meta{env}{ZOIDCMD} = $$meta{zoidcmd} = join ' ', @re;
	return $meta, @re;
}

# See File::Glob for explanation of behaviour
our $_GLOB_OPTS = File::Glob::GLOB_TILDE() | File::Glob::GLOB_QUOTE() | File::Glob::GLOB_BRACE();
our $_NC_GLOB_OPTS = $_GLOB_OPTS | File::Glob::GLOB_NOCHECK();

sub expand_path { # path expansion
	# FIXME add 'failglob' setting (useful in scripts)
	my ($self, $meta, @files) = @_;
	return $meta, @files if $$self{_settings}{noglob};
	my $opts = $$self{_settings}{nullglob} ? $_GLOB_OPTS : $_NC_GLOB_OPTS;
	$opts |= File::Glob::GLOB_NOCASE() if $$self{_settings}{nocaseglob};
	return $meta, map {
		if (/^([\/\w]+=)?(['"])/) { $_ } # quoted
		elsif (/^m\{(.*)\}([imsx]*)$/) { # regex globs
			my @r = regex_glob($1, $2);
			if (@r) { @r }
			else { $_ =~ s/\\\\|\\(.)/$1||'\\'/eg; $_ }
		}
		elsif (/^~|[*?\[\]{}]/) { # normal globs
			# TODO: {x..y} brace expansion
			$_ =~ s#(\\\\)|(?<!\\){([^,{}]*)(?<!\\)}#$1?$1:"\\{$2\\}"#ge
				unless $$self{_settings}{voidbraces}; # brace pre-parsing
			my @r = File::Glob::doglob($_, $opts);
			debug "glob: $_ ==> ".join(', ', @r);
			($_ !~ /^-/) ? (grep {$_ !~ /^-/} @r) : (@r);
			# protect against implict switches as file names
		}
		else { $_ =~ s/\\\\|\\(.)/$1||'\\'/eg; $_ } # remove escapes # FIXME should be done in parse_words like quote removal
	} @files ;
}

sub parse_perl { # parse switches
	my ($self, $block) = @_;
	my ($meta, $string) = @$block;
	my %opts = map {($_ => 1)} split '', $$self{_settings}{perl}{opts};
	$opts{z} = 0 if delete $opts{Z};
	$opts{$_}++ for split '', $$meta{opts};
	$opts{z} = 0 if delete $opts{Z};
	debug 'perl block options: ', \%opts;

	($meta, $string) = $self->_expand_zoid($meta, $string) unless $opts{z};

	if ($opts{g}) { $string = "\nwhile (<STDIN>) {\n\tif (eval {".$string."}) { print \$_; }\n}" }
	elsif ($opts{p}) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n\tprint \$_\n}" }
	elsif ($opts{n}) { $string = "\nwhile (<STDIN>) {\n\t".$string.";\n}" }

	$string = "no strict;\n".$string unless $opts{z};

	return [$meta, $string];
}

sub _expand_zoid {
	my ($self, $meta, $code) = @_;

	my @parts = $$self{stringparser}->split('dezoid_gram', $code);
	my @idx = grep {! ref $parts[$_]} 0 .. $#parts;
	@parts = map {ref($_) ? $$_ : $_} @parts;

	my $pre = '';
	for (@idx) { # probably could be done much cleaner
		my $token = delete $parts[$_];
		my $next = ($_ < $#parts) ? $parts[$_+1] : '';
		my $prev = $_ ? $parts[$_-1] : '';

		my $class = $$self{_settings}{perl}{namespace};
		if ($token =~ /^([\@\$])(\w+)/) {
			my ($sigil, $name) = ($1, $2);
			if ( # global, reserved or non-env var
				$next =~ /^::/
				or grep {$name eq $_} qw/_ ARGV ENV SIG INC JOBS/
				or ! exists $ENV{$name} and ! exists $$meta{env}{$name}
			) { $parts[$_] = $token }
			elsif ($sigil eq '@' or $next =~ /^\[/) { # array
				no strict 'refs';
				$pre .= "Env->import('$token');\n"
					unless defined *{$class.'::'.$name}{ARRAY} and @{$class.'::'.$name};
				$parts[$_] = $token;
			}
			else { $parts[$_] = '$ENV{'.$name.'}' } # scalar
		}
		# else token eq 'ARR'
		elsif ($prev =~ /[\w\}\)\]]$/) { $parts[$_] = '->' }
		else { $parts[$_] = '$shell->' }
	}

	return $meta, $pre . join '', grep defined($_), @parts;
}

# ########## #
# Exec stuff #
# ########## #

sub eval_block { # real exec code
	my ($self, $ref) = @_;
	my $context = $$ref[0]{context};

	if ($$self{parser}{$context}{handler}) {
		debug "going to call handler for context: $context";
		$$self{parser}{$context}{handler}->($ref);
	}
	elsif ($self->can('_do_'.lc($context))) {
		my $sub = '_do_'.lc($context);
		debug "going to call sub: $sub";
		$self->$sub(@$ref);
	}
	else {
		$context
			? error "No handler defined for context $context"
			: bug   'No context defined !'
	}
}

# FIXME FIXME remove _do_* subs below and store them in {parser}

sub _do_subz { # sub shell, forked if all is well
	my ($self, $meta) = @_;
	my $cmd = $$meta{zoidcmd};
	$cmd = $1 if $cmd =~ /^\s*\((.*)\)\s*$/s;
	%$meta = map {($_ => $$meta{$_})} qw/env/; # FIXME also add parser opts n stuff
	# FIXME reset mode n stuff ?
	$self->shell_string($meta, $cmd);
	error $$self{error} if $$self{error}; # forward the error
}

sub _do_cmd {
	my ($self, $meta, $cmd, @args) = @_;
	# exec = exexvp which checks $PATH for us
	# the block syntax to force use of execvp, not shell for one argument list
	# If a command is not found, the exit status shall be 127. If the command name is found,
	# but it is not an executable utility, the exit status shall be 126.
	$$meta{cmdtype} ||= '';
	if ($cmd =~ m|/|) { # executable file
		error 'builtin should not contain a "/"' if $$meta{cmdtype} eq 'builtin';
		error {exit_status => 127}, $cmd.': No such file or directory' unless -e $cmd;
		error {exit_status => 126}, $cmd.': is a directory' if -d _;
		error {exit_status => 126}, $cmd.': Permission denied' unless -x _;
		debug 'going to exec file: ', join ', ', $cmd, @args;
		exec {$cmd} $cmd, @args or error {exit_status => 127}, $cmd.': command not found';
	}
	elsif ($$meta{cmdtype} eq 'builtin' or exists $$self{commands}{$cmd}) { # built-in, not forked I hope
		error {exit_status => 127}, $cmd.': no such builtin' unless exists $$self{commands}{$cmd};
		debug 'going to do built-in: ', join ', ', $cmd, @args;
		local $Zoidberg::Utils::Error::Scope = $cmd;
		$$self{commands}{$cmd}->(@args);
	}
	else { # command in path ?
		debug 'going to exec: ', join ', ', $cmd, @args;
		exec {$cmd} $cmd, @args or error {exit_status => 127}, $cmd.': command not found';
	}
}

sub _do_perl {
	my ($shell, $_Meta, $_Code) = @_;
	my $_Class = $$shell{_settings}{perl}{namespace} || 'Zoidberg::Eval';
	$_Code .= ";\n\$_Class = __PACKAGE__;" if $_Code =~ /package/;
	$_Code  = "package $_Class;\n$_Code";
	undef $_Class;
	debug "going to eval perl code: << '...'\n$_Code\n...";

	local $Zoidberg::Utils::Error::Scope = ['zoid', 0];
	$_ = $$shell{topic};
	$? = $$shell{error}{exit_status} if ref $$shell{error};
	ref($_Code) ? eval { $_Code->() } : eval $_Code;
	if ($@) { # post parse errors
		die if ref $@; # just propagate the exception
		$@ =~ s/ at \(eval \d+\) line (\d+)(\.|,.*\.)$/ at line $1/;
		error { string => $@, scope => [] };
	}
	else {
		$$shell{topic} = $_;
		$$shell{settings}{perl}{namespace} = $_Class if $_Class;
		print "\n" if $$shell{_settings}{interactive}; # ugly hack
	}
}

# ############## #
# some functions #
# ############## #

=item mode [mode]

Without arguments prints the current mode.
With arguments sets the mode.

=cut

sub mode {
	my $self = shift;
	unless (@_) {
		output $$self{_settings}{mode} if $$self{_settings}{mode};
		return;
	}
	my $mode = shift;
	if ($mode eq '-' or $mode eq 'default') {
		$$self{settings}{mode} = undef;
	}
	else {
		my $m = ($mode =~ /::/) ? $mode : uc($mode);
		error $mode.': No such context defined'
			unless grep {lc($mode) eq $_} qw/perl cmd sh/
			or     $$self{parser}{$m}{handler} ; # allow for autoloading
		$$self{settings}{mode} = $mode;
	}
}

=item plug 

TODO

=cut

sub plug {
	my $self = shift;
	my ($opts, $args) = getopt 'list,l verbose,v @', @_;
	if ($$opts{list}) { # list info
		my @items = keys %{$$self{objects}};
		if (@$args) {
			my $re = join '|', @$args;
			@items = grep m/$re/i, @items;
		}
		if ($$opts{verbose}) { # FIXME nicer PLuginHash interface for this
			my ($raw, $meta) = @{ tied( %{$$self{objects}} ) };
			@items = map {
				$_ .' '. $$meta{$_}{module}
			       	. (exists($$raw{$_}) ? ' (loaded)' : '')
			} @items;
		}
		output \@items;
	}
	else { # load plugin
		error 'usage: plug name [args]' unless @$args;
		error $$args[0].': no such plugin'
			unless exists $$self{objects}{ $$args[0] };
		tied( %{$$self{objects}} )->load(@$args);
	}
}

=item unplug

TODO

=cut

sub unplug {
	my $self = shift;
	my ($opt, $args) = getopt 'all,a @', @_;
	if ($$opt{all}) { tied( %{$$self{objects}} )->CLEAR() }
	else {
		error "usage: unplug name" unless @$args == 1;
		delete $$self{objects}{$$args[0]};
	}
}

sub dev_null {} # does absolutely nothing

sub stdin { # stub STDIN input
	my (undef, $prompt, $preput) = @_;
	local $/ = "\n";
	print $prompt if length $prompt;
	my $string = length($preput) ? $preput . <STDIN> : <STDIN> ;
	output $string;
};

sub list_clothes {
	my $self = shift;
	my @return = map {'{'.$_.'}'} sort @{$self->{_settings}{clothes}{keys}};
	push @return, sort @{$self->{_settings}{clothes}{subs}};
	return [@return];
}

# ########### #
# Event logic #
# ########### #

sub broadcast { # eval to be sure we return
	my ($self, $event) = (shift(), shift());
	return unless exists $self->{events}{$event};
	debug "Broadcasting event: $event";
	for my $sub ($$self{events}->stack($event)) {
		eval { $sub->($event, @_) };
		complain("$sub died on event $event ($@)") if $@;
	}
}

sub call { bug 'deprecated routine used' }

# ########### #
# auto loader #
# ########### #

our $ERROR_CALLER;

sub AUTOLOAD {
	my $self = shift;
	my $call = (split/::/,$AUTOLOAD)[-1];

	local $ERROR_CALLER = 1;
	error "Undefined subroutine &Zoidberg::$call called" unless ref $self;
	debug "Zoidberg::AUTOLOAD got $call";

	if (exists $self->{objects}{$call}) {
		no strict 'refs';
		*{ref($self).'::'.$call} = sub { return $self->{objects}{$call} };
		goto \&{$call};
	}
	else { # Shell like behaviour
		debug "No such method or object: '$call', trying to shell() it";
		@_ = ([$call, @_]); # force words parsing
		goto \&Zoidberg::Shell::shell;
	}
}

# ############# #
# Exit routines #
# ############# #

=item C<exit()>

Called by plugins to exit zoidberg -- this ends a interactive C<main_loop()>
loop. This does not clean up or destroy any objects, C<main_loop()> can be
called again to restart it.

=cut

sub exit {
	my $self = shift;
	if (@{$$self{jobs}} and ! $$self{_warned_bout_jobs}) {
		complain "There are unfinished jobs";
		$$self{_warned_bout_jobs}++;
	}
	else {
		message join ' ', @_;
		$self->{_continue} = 0;
	}
	# FIXME this should force ReadLine to quit
}

=item C<round_up()>

This method should be called to clean up the shell objects.
A C<round_up()> method will be called recursively for all secondairy objects.

=cut

sub round_up {
	my $self = shift;
	$self->broadcast('exit');
	if ($self->{round_up}) {
		tied( %{$$self{objects}} )->round_up(); # round up loaded plugins
		Zoidberg::Contractor::round_up($self);
		undef $self->{round_up};
	}
}

sub DESTROY {
	my $self = shift;
	if ($$self{round_up}) {
		warn "Zoidberg was not properly cleaned up.\n";
		$self->round_up;
	}
	delete $OBJECTS{"$self"};
}

package Zoidberg::SettingsHash;

sub TIEHASH {
	my ($class, $ref, $shell) = @_;
	bless [$ref, $shell], $class;
}

sub STORE {
	my ($self, $key, $val) = @_;
	my $old = $$self[0]{$key};
	$$self[0]{$key} = $val;
	$$self[1]->broadcast('set_'.$key, $val, $old); # new, old
	1;
}

#sub set_default {
#	my ($self, $key, @list) = @_;
#	$$self[0]{_SettingsHash_def}{$key} = \@list;
#}

sub DELETE {
	my ($self, $key) = @_;
	my $val = delete $$self[0]{$key};
	$$self[1]->broadcast('set_'.$key, undef, $val); # new, old
	return $val;
}

sub CLEAR { $_[0]->DELETE($_) for keys %{$_[0][0]} }

sub FETCH {
	return $_[0][0]{$_[1]}
#		unless !defined $_[0][0]{$_[1]}
#		and exists $_[0][0]{_SettingsHash_def}{$_[1]};
	# check for default (environment) values
#	for my $def (@{$_[0][0]{_SettingsHash_def}{$_[1]}}) {
#		$def = $ENV{$1} if $def =~ /^\$(.*)/;
#		return $def if defined $def;
#	}
}

sub EXISTS { exists $_[0][0]{$_[1]} }

sub FIRSTKEY { my $a = scalar keys %{$_[0][0]}; each %{$_[0][0]} }

sub NEXTKEY { each %{$_[0][0]} }

package Zoidberg::Eval;

# included to bootstrap a bit of default environment
# for the perl syntax

use strict;
use vars qw/$AUTOLOAD/;

use Data::Dumper;
use Zoidberg::Shell qw/:all/;
use Zoidberg::Utils qw/:error :output :fs regex_glob/;
require Env;

$| = 1;
$Data::Dumper::Sortkeys = 1;

sub pp { # pretty print
	local $Data::Dumper::Maxdepth = shift if $_[0] =~ /^\d+$/;
	if (wantarray) { return Dumper @_ }
	else { print Dumper @_ }
}

{
	no warnings;
	sub AUTOLOAD {
		## Code inspired by Shell.pm ##
		my $cmd = (split/::/, $AUTOLOAD)[-1];
		return undef if $cmd eq 'DESTROY';
		shift if ref($_[0]) eq __PACKAGE__;
		debug "Zoidberg::Eval::AUTOLOAD got $cmd";
		@_ = ([$cmd, @_]); # force words
		unshift @{$_[0]}, '!'
			if lc( $Zoidberg::CURRENT->{settings}{mode} ) eq 'perl';
		goto \&shell;
	}
}

1;

__END__

=back

=head1 AUTOLOADING

Routines not recognised by this object are understood to be either
the name of a plugin, in which case a reference to that object is returned,
or a shell command, in which case Zoidberg tries to execute it.

=head1 AUTHOR

Joel Berger, E<lt>joel.a.berger@gmail.comE<gt>

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

R.L. Zwart, E<lt>carl0s@users.sourceforge.netE<gt>

Copyright (c) 2011 Jaap G Karssenberg and Joel Berger. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/language/misc/Artistic.html>
and L<http://www.gnu.org/copyleft/gpl.html>

=head1 SEE ALSO

L<zoid>(1), L<zoiddevel>(1),
L<Zoidberg::Shell>,
L<http://github.com/jberger/Zoidberg>

=cut
