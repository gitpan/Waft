
use Test;
BEGIN { plan tests => 3 };

use strict;
BEGIN { eval { require warnings } ? 'warnings'->import : ( $^W = 1 ) }

use English qw( -no_match_vars );

use lib 't';
require Waft::Test::STDERR;

warn "$PROGRAM_NAME-1\n";

my $gotten = do {
    my $stderr = Waft::Test::STDERR->new;

    warn "$PROGRAM_NAME-2\n";

    $stderr->get;
};

warn "$PROGRAM_NAME-3\n";

ok( $gotten !~ / \Q$PROGRAM_NAME\E-1 /xms );
ok( $gotten =~ / \Q$PROGRAM_NAME\E-2 /xms );
ok( $gotten !~ / \Q$PROGRAM_NAME\E-3 /xms );
