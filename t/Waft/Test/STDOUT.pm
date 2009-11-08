package Waft::Test::STDOUT;

use strict;
use vars qw( $VERSION );
BEGIN { 'warnings'->import if eval { require warnings } }

use Carp;
use Symbol;

$VERSION = '1.0';

binmode STDOUT;
select( ( select(STDOUT), $| = 1 )[0] );

sub new {
    my ($class) = @_;

    my $duplicate = gensym;

    open $duplicate, '>&STDOUT'
        or croak 'Failed to duplicate STDOUT';

    open STDOUT, '>t/STDOUT.test'
        or croak 'Failed to open STDOUT piped to file';

    bless $duplicate, $class;

    return $duplicate;
}

sub DESTROY {
    my ($duplicate) = @_;

    open STDOUT, '>&=' . fileno $duplicate
        or croak 'Failed to return STDOUT';

    unlink 't/STDOUT.test';

    return;
}

sub get {

    my $stdout = gensym;
    open $stdout, '<t/STDOUT.test'
        or croak 'Failed to open file piped from STDOUT';
    binmode $stdout;

    return do { local $/; <$stdout> };
}

1;
