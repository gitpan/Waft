
use Test;
BEGIN { plan tests => 3 };

use strict;
BEGIN { eval { require warnings } ? 'warnings'->import : ( $^W = 1 ) }

{
    package Waft::Test::Mixin3;

    sub mixin1 { 3 }

    sub mixin2 { 3 }

    sub mixin3 { 3 }
}

use lib 't';
use Waft with => 'Waft::Test::Mixin1', '::Test::Mixin2', 'Waft::Test::Mixin3';

ok( __PACKAGE__->mixin1 == 1 );
ok( __PACKAGE__->mixin2 == 2 );
ok( __PACKAGE__->mixin3 == 3 );
