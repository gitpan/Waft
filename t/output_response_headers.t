
use Test;
BEGIN { plan tests => 4 + 3 };

use strict;
BEGIN { 'warnings'->import if eval { require warnings } }

use base qw( Waft );

use lib 't';
require Waft::Test::STDOUT;

{
    my $stdout = Waft::Test::STDOUT->new;

    my $obj = __PACKAGE__->new;
    $obj->header('Content-Type: text/plain; charset=UTF-8');
    $obj->header('Content-Type: image/jpeg');
    $obj->content_type('text/html; charset=UTF-8');
    my $content_type_before_output = $obj->content_type;
    $obj->output;

    my $gotten = $stdout->get;

    undef $stdout;

    ok( not defined $content_type_before_output );
    ok($gotten, "Content-Type: text/html; charset=UTF-8\x0D\x0A\x0D\x0A");
    ok( not defined $obj->http_status );
    ok($obj->content_type, 'text/html; charset=UTF-8');
}

{
    my $stdout = Waft::Test::STDOUT->new;

    my $obj = __PACKAGE__->new;
    $obj->header('Status: 304 Not Modified');
    $obj->header('Status: 403 Forbidden');
    $obj->http_status('200 OK');
    my $http_status_before_output = $obj->http_status;
    $obj->output;

    my $gotten = $stdout->get;

    undef $stdout;

    ok( not defined $http_status_before_output );
    ok( $gotten, qr/\A Status: \x20 200 \x20 OK \x0D\x0A /xms );
    ok($obj->http_status, '200 OK');
}
