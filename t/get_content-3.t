
use Test;
BEGIN { plan tests => 1 };

use strict;
BEGIN { 'warnings'->import if eval { require warnings } }

use base qw( Waft );

ok( not defined __PACKAGE__->new->get_content( sub {} ) );
