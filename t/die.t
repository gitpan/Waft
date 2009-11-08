
use Test;
BEGIN { plan tests => 4 };

use strict;
BEGIN { 'warnings'->import if eval { require warnings } }

use base qw( Waft );

use lib 't';
require Waft::Test::STDERR;

my $obj = __PACKAGE__->new;

eval { $obj->die('error') };
ok( $@, qr/\A Error: \x20 error \x20 at \x20 /xms );

{
    my $stderr = Waft::Test::STDERR->new;

    my @return_values = $obj->die('error');
    ok( scalar @return_values, 2 );
    ok($return_values[0], 'internal_server_error');
    ok($return_values[1], 'error');
}
