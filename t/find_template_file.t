
use Test;
BEGIN { plan tests => 16 };

use strict;
BEGIN { eval { require warnings } ? 'warnings'->import : ( $^W = 1 ) }

use lib 't';
require Waft::Test::FindTemplateFile;

my $obj = Waft::Test::FindTemplateFile->new;

my ($template_file, $template_class);

($template_file, $template_class)
    = $obj->find_template_file('own_template.html');
ok( $template_file eq 't/Waft/Test/FindTemplateFile/own_template.html');
ok( $template_class eq 'Waft::Test::FindTemplateFile' );

($template_file, $template_class)
    = $obj->find_template_file('own_module.pm');
ok( $template_file eq 't/Waft/Test/FindTemplateFile.template/own_module.pm');
ok( $template_class eq 'Waft::Test::FindTemplateFile' );

($template_file, $template_class)
    = $obj->find_template_file('base_template.html');
ok( $template_file eq 't/Waft/Test/base_template.html');
ok( $template_class eq 'Waft::Test' );

($template_file, $template_class)
    = $obj->find_template_file('base_module.pm');
ok( $template_file eq 't/Waft/Test.template/base_module.pm');
ok( $template_class eq 'Waft::Test' );

Waft::Test::FindTemplateFile->set_allow_template_file_exts( () );

{
    local $Waft::Cache = 0;

    ($template_file, $template_class)
        = $obj->find_template_file('own_template.html');
    ok( $template_file
        eq 't/Waft/Test/FindTemplateFile.template/own_template.html'
    );
    ok( $template_class eq 'Waft::Test::FindTemplateFile' );
}

($template_file, $template_class)
    = $obj->find_template_file('base_template.html');
ok( $template_file eq 't/Waft/Test/base_template.html');
ok( $template_class eq 'Waft::Test' );

Waft::Test->set_allow_template_file_exts( () );

{
    local $Waft::Cache = 0;

    ($template_file, $template_class)
        = $obj->find_template_file('base_template.html');
    ok( $template_file eq 't/Waft/Test.template/base_template.html');
    ok( $template_class eq 'Waft::Test' );
}

{
    local $Waft::Cache = 0;

    Waft::Test::FindTemplateFile->set_allow_template_file_exts( qw( .pm ) );

    ($template_file, $template_class)
        = $obj->find_template_file('own_module.pm');
    ok( $template_file eq 't/Waft/Test/FindTemplateFile/own_module.pm');
    ok( $template_class eq 'Waft::Test::FindTemplateFile' );
}
