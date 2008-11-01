
use Test;
BEGIN { plan tests => 2 };

use strict;
BEGIN { eval { require warnings } ? 'warnings'->import : ( $^W = 1 ) }

require Waft;

my $text = qq{"&'45678\t<br />\n};
my $filtered
    = "&quot;&amp;&#39;45678 &nbsp; &nbsp; &nbsp; &nbsp;&lt;br /&gt;<br />\n";

ok( Waft->text_filter($text) eq $filtered );
ok( Waft->text_filter("$text$text") eq "$filtered$filtered" );
