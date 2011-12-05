package Zoidberg::Fish::Feature;

our $VERSION = '0.97';

use strict;
#use Zoidberg::Utils qw/:default path getopt output_is_captured/;
use base 'Zoidberg::Fish';

use version 0.77;

# feature loading needs to happen at compile time, and as soon as possible.
our @feature_keywords;
BEGIN {
  { # block for last-ing out
    last if ($^V < v5.10.0);

    require feature;

    my $import_version = ':5.10';
    push @feature_keywords, qw'say state given';

    if ( $^V >= v5.12.0 ) {
      $import_version = ':5.12'; 
    }

    if ( $^V >= v5.14.0 ) {
      $import_version = ':5.14'; # s///r
    }

    feature->import($import_version);
    print STDERR "Additional Perl features '$import_version' loaded\n\t'@feature_keywords' added as keywords.\n";

  }
}

sub init {
  my $plugin = shift;
  $plugin->add_features();
}

sub add_features {
  my $plugin = shift;
  $plugin->add_commands(@feature_keywords) if @feature_keywords;
}

