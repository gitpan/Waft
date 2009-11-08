
use Test;
BEGIN { plan tests => 3 };

use strict;
BEGIN { 'warnings'->import if eval { require warnings } }

use English qw( -no_match_vars );
use Symbol;

use lib 't';
require Waft::Test::STDOUT;

my $duplicate = gensym;

open $duplicate, '>&STDOUT'
    or die 'Failed to duplicate STDOUT';

open STDOUT, '>t/STDOUT.tmp'
    or die 'Failed to open STDOUT piped to file';

print "$PROGRAM_NAME-1\n";

my $gotten = do {
    my $stdout = Waft::Test::STDOUT->new;

    print "$PROGRAM_NAME-2\n";

    $stdout->get;
};

print "$PROGRAM_NAME-3\n";

open STDOUT, '>&=' . fileno $duplicate
    or die 'Failed to return STDOUT';

unlink 't/STDOUT.tmp';

ok( $gotten !~ / \Q$PROGRAM_NAME\E-1 /xms );
ok( $gotten =~ / \Q$PROGRAM_NAME\E-2 /xms );
ok( $gotten !~ / \Q$PROGRAM_NAME\E-3 /xms );
