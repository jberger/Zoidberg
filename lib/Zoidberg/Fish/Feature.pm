package Zoidberg::Fish::Feature;

our $VERSION = '0.97';

use strict;
use Zoidberg::Utils qw/message/;
use base 'Zoidberg::Fish';

use version 0.77;

# feature loading needs to happen at compile time, and as soon as possible.
our $import_version;
our @feature_keywords;
BEGIN {
  { # block for last-ing out
    $import_version = 0;

    last if ($^V < v5.10.0);

    $import_version = ':5.10';
    push @feature_keywords, qw'say state given when default';

    if ( $^V >= v5.12.0 ) {
      $import_version = ':5.12'; 
    }

    if ( $^V >= v5.14.0 ) {
      $import_version = ':5.14'; # s///r
    }

  }
}

use if $import_version, feature => $import_version;

sub init {
  my $plugin = shift;
  $plugin->add_features();
}

sub add_features {
  my $plugin = shift;
  if (@feature_keywords) {
    no strict 'refs';
    my @commands = map { $_ => \&{ __PACKAGE__ . '::' . $_ } } @feature_keywords;
    $plugin->add_commands(\@commands);
    message "Additional Perl features '$import_version' loaded\n\t'@feature_keywords' added as keywords.\n";
  }
}

