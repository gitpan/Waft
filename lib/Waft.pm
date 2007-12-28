package Waft;

use 5.005;
use strict;
use vars qw( $VERSION );
use Carp;
use English qw( -no_match_vars );
use Fcntl;
use Symbol;
require B;
require File::Spec;

$VERSION = '0.52';

sub waft {
    my ($self, @args) = @_;

    my @porter;

    if (ref $self) {
        @porter = @args;
    }
    else {
        ($self, @porter) = $self->new(@args);
    }

    my $stash = $self->stash;

    $stash->{url} = _get_url();

    {
        no strict 'refs';

        if ($stash->{use_utf8}) {
            eval q{binmode select, ':utf8'};
        }
        else {
            binmode select;
        }
    }

    $self->Waft::_load_query_param;

    @porter = $self->Waft::_call_method( $self->can('begin'), @porter );
    @porter = $self->Waft::_controller(@porter);
    @porter = $self->end(@porter);

    return wantarray ? @porter : $porter[0];
}

sub new {
    my ($class, @args) = @_;

    my @porter;

    if (ref $args[0] eq 'HASH') {
        (my $arg_hashref, @porter) = @args;
        @args = %$arg_hashref;
    }

    my $self;
    tie %$self, 'Waft::Object';
    bless $self, $class;

    my $stash = $self->stash;

    %$stash = (
        content_type   => 'text/html',
        headers        => [],
        @args,
    );

    if ($stash->{use_utf8}) {
        eval { require 5.008001 };

        if ($EVAL_ERROR) {
            carp "use_utf8; $EVAL_ERROR";
        }
    }

    return wantarray ? ($self, @porter) : $self;
}

# simulate Class::Std::Utils::ident
sub ident {
    my ($obj) = @_;

    my $blessed_class = ref $obj;

    bless $obj;
    croak 'invalid argument' if "$obj" !~ / 0x(\w+) /x;
    my $id = hex $1;

    bless $obj, $blessed_class;

    return $id;
}

my %Stash;

sub stash {
    my ($self, $package) = @_;
    return $Stash{ident $self}{$package || caller} ||= {};
}

sub DESTROY {
    my ($self) = @_;
    delete $Stash{ident $self};
    return;
}

sub _get_url () {
    my $updir = $ENV{PATH_INFO} || q{};
    my $updirs = $updir =~ s{ /[^/]* }{../}gx;

    my $url;

    if (defined $ENV{REQUEST_URI} and $ENV{REQUEST_URI} =~ /\A ([^?]+) /x) {
        $url = $1;

        for (my $i = 0; $i < $updirs; ++$i) {
            $url =~ s{ /[^/]* \z}{}x;
        }
    }
    else {
        $url = $ENV{SCRIPT_NAME}
               || eval q{ use FindBin qw( $Script ); $Script };
    }

    return $url =~ m{ ([^/]+) \z}x ? "$updir$1" : './';
}

sub _load_query_param {
    my ($self) = @_;

    my $stash = $self->stash;
    my $page = $self->query->param('s');
    my $submitted;

    if (defined $page) {
        $submitted = 1;
    }
    else {
        $page = $self->query->param('p');
    }

    if (defined $page) {
        if ( File::Spec->file_name_is_absolute($page)
             or $page =~ m{ [/\\]{2,} }x
             or $page =~ m{ (?<! [^/\\] ) \.\.? (?! [^/\\] ) }x
             or $page =~ m{ :: }x
             or $page eq 'CURRENT'
             or $page eq 'TEMPLATE'
             or $self->page_id($page) =~ / __indirect \z/x
        ) {
            warn qq{invalid requested page "$page"};
            $page = 'default.html';
        }

        $stash->{page} = $page;
    }
    else {
        $stash->{page} = 'default.html';
    }

    if ($submitted) {
        my $page_id = $self->page_id;
        my $global_action;

        PARAM:
        for my $param_name ($self->query->param) {
            my $action_id = ( $param_name =~ / ([^.]*) /x )[0];

            next PARAM if    $action_id =~ /(?: \A | _ ) direct   \z/x
                          or $action_id =~ /(?: \A | _ ) indirect \z/x
                          or $action_id =~ /\A global_ /x
                          ;

            if ( $self->can("__${page_id}__$action_id") ) {
                $stash->{action} = $param_name;
                last PARAM;
            }

            next PARAM if defined $global_action;

            if ( $self->can("global_$action_id") ) {
                $global_action = "global_$param_name";
            }
        }

        if (not defined $stash->{action}) {
            if (defined $global_action) {
                $stash->{action} = $global_action;
            }
            elsif ( $self->can("__${page_id}__submit") ) {
                $stash->{action} = 'submit';
            }
            elsif ( $self->can('global_submit') ) {
                $stash->{action} = 'global_submit';
            }
            else {
                warn 'requested parameters do not match with defined action';
                $stash->{action} = 'direct';
            }
        }
    }
    else {
        $stash->{action} = 'direct';
    }

    if ( defined( my $joined_values = $self->query->param('v') ) ) {
        my @key_values_pairs = split /\x20/, $joined_values, -1;

        for my $key_values_pair (@key_values_pairs) {
            my ($key, @values) = split /-/, $key_values_pair, -1;

            $self->set_values(
                _unescape($key) => map { _unescape($_) } @values
            );
        }
    }

    return;
}

sub query {
    my ($self) = @_;

    my $stash = $self->stash;

    return $stash->{query} if $stash->{query};

    require CGI;
    $stash->{query} = CGI->new;

    if ($stash->{use_utf8}) {
        eval qq{\n# line } . __LINE__ . q{ "} . __FILE__ . qq{"\n} . q{
            use CGI 3.21 qw( -utf8 ); # -utf8 pragma is for 3.31 or more
        };

        if ($EVAL_ERROR) {
            warn "use_utf8; $EVAL_ERROR";
        }
        elsif (CGI->VERSION < 3.31) {
            $stash->{query}->charset('utf-8');
        }
    }

    return $stash->{query};
}

sub page_id {
    my ($self, $page) = @_;

    if (not defined $page) {
        $page = $self->stash->{page};
    }

    $page =~ s{ \.[^/:\\]* \z}{}x;
    $page =~ tr/0-9A-Za-z_/_/c;

    return $page;
}

sub _unescape ($) {
    my ($string) = @_;
    $string =~ s/ %(2[05d]) / pack 'H2', $1 /egx;
    return $string;
}

sub set_values {
    my ($self, $key, @values) = @_;
    @{ $self->Waft::_value->{$key} } = @values;
    return;
}

sub _value {
    my ($self) = @_;
    return tied %$self;
}

sub set_value {
    my ($self, $key, $value) = @_;
    $self->set_values($key, $value);
    return;
}

sub begin {
    my ($self, @args) = @_;
    return 'CURRENT', @args;
}

sub _call_method {
    my ($self, $method_coderef, @porter) = @_;

    my $stash = $self->stash;

    @porter = $self->$method_coderef(@porter);
    return @porter if $stash->{output};

    my $page = shift @porter;
    my $action;

    if (ref $page eq 'ARRAY') {
        ($page, $action) = @$page;
    }

    my $method = B::svref_2object($method_coderef)->GV->NAME;
    my $begin_or_before = $method eq 'begin' || $method eq 'before';

    if (not defined $page) {
        $page = $begin_or_before ? 'CURRENT' : 'TEMPLATE';
    }

    return $self->Waft::_call_template(@porter) if $page eq 'TEMPLATE';

    if (defined $action) {
        $stash->{action} = $action;
    }
    elsif ( not ($begin_or_before and $page eq 'CURRENT') ) {
        $stash->{action} = 'indirect';
    }

    if ($page ne 'CURRENT') {
        $stash->{page} = $page;
    }

    return @porter;
}

sub _call_template {
    my ($self, @porter) = @_;

    my $stash = $self->stash;
    my $page = 'TEMPLATE';
    my $action;

    my $loop_count;
    TEMPLATE:
    while ($page eq 'TEMPLATE') {
        die 'deep recursion when template processing' if ++$loop_count > 4;

        @porter = $self->Waft::_call_template_($stash->{page}, @porter);
        return @porter if $stash->{output};

        $page = shift @porter;

        if (ref $page eq 'ARRAY') {
            ($page, $action) = @$page;
        }

        die 'no content' if not defined $page;
    }

    $stash->{action} = defined $action ? $action : 'indirect';

    if ($page ne 'CURRENT') {
        $stash->{page} = $page;
    }

    return @porter;
}

sub _call_template_ {
    my ($self, $page, @args) = @_;

    my @return_values;

    my $template_coderef = $self->Waft::_compile_template_file($page);
    die $template_coderef if ref $template_coderef ne 'CODE';

    return $self->$template_coderef(@args);
}

sub _convert ($$) {
    my ($template_ref, $package) = @_;

    my $break =   $$template_ref =~ /( \x0d\x0a | [\x0a\x0d] )/x ? $1
                :                                                  "\n";

    my $convert_text_part = sub ($) {
        my ($text_part) = @_;

        my $code;

        if ($text_part
                =~ / ([^\x0a\x0d]*) ( (?: \x0d\x0a | [\x0a\x0d] ) .* ) /xs
        ) {
            my ($first_line, $after_first_break) = ($1, $2);

            if (length $first_line) {
                $first_line =~ s/(['\\])/\\$1/g;
                $code .= qq{\$Waft::self->output('$first_line');};
            }

            $after_first_break =~ s/(["\$\@\\])/\\$1/g;

            my $breaks = $break x (
                  $after_first_break =~ s/\x0d\x0a/\\x0d\\x0a/g
                + $after_first_break =~ s/\x0a/\\x0a/g
                + $after_first_break =~ s/\x0d/\\x0d/g
                - 1
            );

            $code .=   $break
                     . qq{\$Waft::self->output("$after_first_break");$breaks};
        }
        else {
            $text_part =~ s/(['\\])/\\$1/g;
            $code = qq{\$Waft::self->output('$text_part');};
        }

        return $code;
    };

    $$template_ref = "%>$$template_ref<%";

    $$template_ref =~ s{ (?<= %> ) (?! <% ) (.+?) (?= <% ) }
                       { $convert_text_part->($1) }egxs;

    $$template_ref
        =~ s{<%(?!\s*[\x0a\x0d]=[A-Za-z])\s*t(?:ext)?\s*=(.*?)%>}
            {\$Waft::self->output(\$Waft::self->text_filter($1));}gs;

    $$template_ref
        =~ s{<%(?!\s*[\x0a\x0d]=[A-Za-z])\s*(?:w(?:ord)?\s*)?=(.*?)%>}
            {\$Waft::self->output(\$Waft::self->word_filter($1));}gs;

    $$template_ref
        =~ s{%>|<%}
            {}g;

    $$template_ref = $break
                     . "package $package;"
                     . 'my $response = sub {'
                     .     'local $Waft::self = $_[0];'
                     .     $$template_ref . $break
                     . "};$break"
                     ;

    return;
}

sub _search_template_file {
    my ($self, $page) = @_;

    my $template_file_path_cache
        = $self->stash->{template_file_path_cache} ||= {};

    return @{ $template_file_path_cache->{$page} }
        if $template_file_path_cache->{$page};

    return @{ $template_file_path_cache->{$page} }
           = $self->Waft::_search_template_file_($page);
}

sub _search_template_file_ {
    my $self = $_[0];
    my $page = $_[1];

    my $stash = $self->stash;

    if (File::Spec->file_name_is_absolute($page)) {
        if (-f $page) {
            return $page, ref $self;
        }
        else {
            warn qq{template file "$page" is not found};
            return;
        }
    }

    if (defined $stash->{template_dir}) {
        my $path = File::Spec->catdir($stash->{template_dir}, $page);

        if (-f $path) {
            return $path, ref $self;
        }
        else {
            warn qq{template file "$path" is not found};
            return;
        }
    }




    my ($search, %seen, $_get_lib_dir);

    $search = sub ($) {
        my ($class) = @_;
        return if $seen{$class}++;

        my $file = $class;
        $file =~ s{::}{/}g;
        $file .= ".template/$page";

        for my $lib_dir ( $_get_lib_dir->($class) ) {
            my $file = "$lib_dir/$file";
            return $file, $class if -f $file;
        }

        my @super_classes = do { no strict 'refs'; @{ "${class}::ISA" } };
        for my $super_class (@super_classes) {
            if ( my ($file, $class) = $search->($super_class) ) {
                return $file, $class;
            }
        }

        return;
    };

    $_get_lib_dir = sub ($) {
        my ($class) = @_;

        my $class_file = $class;
        $class_file =~ s{::}{/}g;
        $class_file .= '.pm';

        return @INC if not defined $INC{$class_file};
        return @INC if $INC{$class_file} !~ m{\A (.+) /\Q$class_file\E \z}x;
        return $1;
    };

    if ( my ($path, $class) = $search->(ref $self) ) {
        return $path, $class;
    }




    warn qq{template file "$page" is not found};
    return;
}

my %RESPONSE_CACHE;
sub _compile_template_file ($$) {
    my $self = $_[0];
    my $file = $_[1];

    my ($path, $package) = _search_template_file($self, $file)
        or return 'Not Found';

    my @stat = stat $path
        or do {
            warn qq{failed to stat template file "$path"};
            return -f $path ? 'Forbidden' : 'Not Found';
        };

    my $datetime
        = do {
            my @localtime = localtime $stat[9];

            sprintf '%d%02d%02d%02d%02d%02d' => ($localtime[5] + 1900,
                                                 $localtime[4] + 1,
                                                 @localtime[3, 2, 1, 0]);
        };

    my $response_name = "${package}::$file";

    my $response_id = "$response_name-$datetime";

    # return
    $RESPONSE_CACHE{$response_id}
    or do {
        my $delete_old_cache = sub {
            my $response_id_regexp = qr/\A\Q$response_name\E-\d{14}\z/;

            for (keys %RESPONSE_CACHE) {
                if (/$response_id_regexp/) {
                    $Waft::Debug and debug_log(qq{delete "$_"});
                    delete $RESPONSE_CACHE{$_};
                }
            }

            # return;
        };

        my $read_template_file = sub {
            sysopen((my $sym = gensym), $path, O_RDONLY)
                or do {
                    warn qq{failed to open template file "$path"};
                    return -f $path ? 'Forbidden' : 'Not Found';
                };

            binmode $sym;

            read($sym, my $template, $stat[7]) == $stat[7]
                or do {
                    warn qq{failed to read template file "$path"};
                    return 'Internal Error';
                };

            close $sym
                or do {
                    warn qq{failed to close template file "$path"};
                    return 'Internal Error';
                };

my $auto_output_waft_tags = sub ($) {
    my ($code) = @_;

    return $code if $code =~ m{ \b (?:   output_waft_tags
                                       | (?: (?i) waft(?: \s+ | _ )tag s? )
                                       | form_elements            # deprecated
                                   ) \b }x;

    $code =~ s{(?<= "> )}
              {<% Waft::_auto_output_waft_tags(\$Waft::self); %>}x;

    return $code;
};

$template =~ s{ (?<= <form \b ) (.+?) (?= </form> ) }
              { $auto_output_waft_tags->($1) }egixs;

            # return
            \$template;
        };

        my $stash = $self->{stash};

        if (defined $stash->{temporary_dir}) {
            (my $temporary_name = $response_name) =~ s|(?<!:)::(?!:)|-|g;
                $temporary_name                   =~ s|[/:\\]|-|g;

            my $temporary = File::Spec->catdir(
                                $stash->{temporary_dir},
                                $temporary_name
                            )
                            . "-$datetime.pl";

            # return
            $Waft::Debug and debug_log(qq{require "$temporary"});
            $RESPONSE_CACHE{$response_id} = eval "require '$temporary'"
                                            || do {
                $Waft::Debug and debug_log(qq{failure "$temporary"});

                &$delete_old_cache;

                my $sym = gensym;

                if (opendir $sym, $stash->{temporary_dir}) {
                    my $temporary_file_regexp
                        = qr/\A\Q$temporary_name\E-\d{14}\.pl\z/;

                    while (defined (my $file = readdir $sym)) {
                        next if $file !~ /$temporary_file_regexp/;

                        my $path = File::Spec->catdir(
                            $stash->{temporary_dir}, $file
                        );

                        $Waft::Debug and debug_log(qq{unlink "$path"});
                        unlink $path
                            or warn(
                               qq{failed to delete old temporary file "$path"}
                            );
                    }

                    closedir $sym
                      or warn(
                       qq{failed to close directory "$stash->{temporary_dir}"}
                      );
                }
                else {
                    warn(
                        qq{failed to open directory "$stash->{temporary_dir}"}
                    );
                }

                my $template_ref = &$read_template_file;
                return $template_ref if ref $template_ref ne 'SCALAR';

                _convert($template_ref, $package);

                sysopen $sym, $temporary, O_CREAT | O_EXCL | O_WRONLY, 0400
                    or do {
                        warn(
                            qq{failed to create temporary file "$temporary"}
                        );

                        return 'Internal Error';
                    };

                binmode $sym;

                local $, = q{};
                print $sym qq{# line 1 "$file"}, $$template_ref
                    or do {
                        warn(
                            qq{failed to write to temporary file "$temporary"}
                        );

                        return 'Internal Error';
                    };

                close $sym
                    or do {
                        warn(
                            qq{failed to close temporary file "$temporary"}
                        );

                        return 'Internal Error';
                    };

                # return
                $Waft::Debug and debug_log(qq{convert "${package}::$file"});
                eval qq{\n# line } . __LINE__ . q{ "} . __FILE__
                     . qq{"\nrequire '$temporary';}
                or do {
                    warn $@;

                    unlink $temporary
                        or warn(
                            qq{failed to delete temporary file "$temporary"}
                        );

                    return 'Internal Error';
                };
            };
        }
        else {
            &$delete_old_cache;

            my $template_ref = &$read_template_file;
            return $template_ref if ref($template_ref) ne 'SCALAR';

            _convert($template_ref, $package);

            if ($stash->{use_utf8}) {
                utf8::encode($file);
            }

            # return
            $Waft::Debug and debug_log(qq{eval "${package}::$file"});
            $RESPONSE_CACHE{$response_id}
                = eval qq{\n# line 1 "$file" $$template_ref}
                  || do {
                      warn $@;
                      return 'Internal Error';
                  };
        }
    }
}

sub output {
    my ($self, @strings) = @_;

    my $stash = $self->stash;

    if (not $stash->{output}) {
        $self->Waft::_respond_headers;
        $stash->{output} = 1;
    }

    return if not @strings;

    print @strings;

    return;
}

sub _respond_headers {
    my ($self, $content_length) = @_;

    my $stash = $self->stash;

    for my $header (@{ $stash->{headers} }) {
        print "$header\x0d\x0a";
    }

    if (defined $content_length) {
        if (not grep /\A Content-Length: /ix, @{ $stash->{headers} }) {
            print "Content-Length: $content_length\x0d\x0a";
        }
    }

    if (not grep /\A Content-Type: /ix, @{ $stash->{headers} }) {
        print "Content-Type: $stash->{content_type}\x0d\x0a";
    }

    print "\x0d\x0a";
}

sub output_waft_tags {
    my ($self, @args) = @_;
    $self->output( $self->waft_tags(@args) );
    return;
}

sub waft_tags {
    my ($self, @args) = @_;

    my $stash = $self->stash;

    return '<input name="s" type="hidden" value="'
           . $self->html_escape($stash->{page})
           . '" /><input name="v" type="hidden" value="'
           . $self->html_escape( $self->join_values(@args) )
           . '" />';
}

sub _auto_output_waft_tags ($) {
    my ($self) = @_;
    $self->output_waft_tags('ALL_VALUES');
    return;
}

sub html_escape {
    shift;
    my @value = @_;

    for (@value) {
        defined or do {
            carp 'Use of uninitialized value' if $^W;
            next;
        };

        s/&/&amp;/g;
        s/"/&quot;/g;
        s/'/&#39;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
    }

    wantarray ? @value : $value[0];
}

sub join_values {
    my $value = shift->Waft::_value;

    my @values =   @_ == 1
                   && defined $_[0]
                   && $_[0] eq 'ALL_VALUES' ? ([keys %$value])
                 :                            @_
                 ;

    my %value;

    while (@values) {
        my $key = shift @values;

        if (ref $key eq 'ARRAY') {
            KEY:
            for my $key (@$key) {
                if (not defined $key) {
                    if ($WARNING) {
                        carp 'Use of uninitialized value';
                    }

                    $key = q{};
                }

                next KEY if not exists $value->{$key};

                $value{_escape_key($key)} = _escape_values(
                    $value->{$key} ? @{ $value->{$key} } : ()
                );
            }
        }
        elsif (defined $key) {
            if (not @values and $WARNING) {
                carp 'Odd number of elements in hash assignment';
            }

            my $value = shift @values;

            $value{_escape_key($key)}
                = _escape_values(ref $value eq 'ARRAY' ? @$value : $value);
        }
        else {
            if ($WARNING) {
                carp 'Use of uninitialized value';
            }
        }
    }

    return join q{ }, map { $_ . $value{$_} } sort keys %value;
}

sub _escape_key {
    my ($key) = @_;
    $key =~ s/([ %-])/'%' . unpack 'H2', $1/eg;
    return $key;
}

sub _escape_values {
    my (@values) = @_;

    for my $value (@values) {
        if (defined $value) {
            $value =~ s/([ %-])/'%' . unpack 'H2', $1/eg;
        }
        else {
            if ($WARNING) {
                carp 'Use of uninitialized value';
            }

            $value = q{};
        }
    }

    return join q{}, map { "-$_" } @values;
}

BEGIN {
    # export 'expand' for text_filter
    eval q{ use Text::Tabs 2005.0824 };

    # generate simple expand if faild to use Text::Tabs
    if ($EVAL_ERROR) {
        *expand = sub ($) {
            my ($value) = @_;
            $value =~ s/\t/        /g;
            return $value;
        };
    }
}

sub text_filter {
    my $self  = shift;
    my @value = @_;

    for (@value) {
        defined or do {
            carp 'Use of uninitialized value' if $^W;
            next;
        };

        $_ = $self->html_escape(expand $_);
        s{(\s) }{$1&nbsp;}g;
        s{(\x0d\x0a|[\x0a\x0d])}{<br />$1}g;
    }

    wantarray ? @value : $value[0];
}

sub url {
    my $self = shift;

    my ($value, $stash) = ($self->Waft::_value, $self->stash);

    if (@_) {
        my @query_string;

        my $page = shift;

        if (ref $page eq 'ARRAY') {
            ($page) = @$page;
        }

        if (not defined $page) {
            $page = 'CURRENT';
        }

        if ($page eq 'CURRENT') {
            $page = $stash->{page};
        }

        if ($page ne 'default.html') {
            push @query_string,
                join '=' => $self->url_encode('p', $page);
        }

        if ( my $joined_value = $self->join_values(@_) ) {
            push @query_string,
                join '=' => $self->url_encode(
                                'v', $joined_value
                            );
        }

        # return
        @query_string
            ? $stash->{url} . '?' . join '&', @query_string
            : $stash->{url};
    }
    else {
        $stash->{url};
    }
}

sub url_encode {
    my $use_utf8 = shift->stash->{use_utf8};
    my @value    = @_;

    for (@value) {
        defined or do {
            carp 'Use of uninitialized value' if $^W;
            next;
        };

        if ($use_utf8) {
            utf8::encode($_);
        }

        s/([^ .\w-])/'%' . unpack 'H2', $1/eg;
        tr/ /+/;
    }

    wantarray ? @value : $value[0];
}

sub word_filter {
    shift->html_escape(@_);
}

sub include {
    my ($self, $page, @args) = @_;
    $page =~ s/.+:://; # deprecated
    return $self->Waft::_call_template_($page, @args);
}

sub header {
    my ($self, @header_blocks) = @_;

    my $stash = $self->stash;

    for my $header_block (@header_blocks) {
        my @header_lines = grep { length } split /[\x0a\x0d]+/, $header_block;
        push @{ $stash->{headers} }, @header_lines;
    }

    return;
}

sub action {
    shift->stash->{action};
}

sub page {
    shift->stash->{page};
}

sub _controller {
    my ($self, @porter) = @_;

    my $stash = $self->stash;

    my $loop_count;
    CONTROLLER:
    while (not $stash->{output}) {
        die 'deep recursion on controller' if ++$loop_count > 4;

        @porter = $self->Waft::_call_method( $self->can('before'), @porter );
        last CONTROLLER if $stash->{output};

        if (my $action_coderef = $self->Waft::_search_action_method) {
            @porter = $self->Waft::_call_method($action_coderef, @porter);
        }
        else {
            @porter = $self->Waft::_call_template(@porter);
        }
    }

    return @porter;
}

sub before {
    my ($self, @args) = @_;
    return 'CURRENT', @args;
}

sub _search_action_method {
    my ($self) = @_;

    my $stash = $self->stash;
    my $page_id = $self->page_id;

    if ($stash->{action} eq 'indirect') {
        return    $self->can("__${page_id}__indirect")
               || $self->can("__${page_id}")
               || $self->can('global_indirect')
               ;
    }
    elsif ($stash->{action} eq 'direct') {
        return    $self->can("__${page_id}__direct")
               || $self->can("__${page_id}")
               || $self->can('global_direct')
               ;
    }
    elsif ($stash->{action} =~ /\A (global_[^.]*) /x) {
        return $self->can($1);
    }
    elsif ($stash->{action} =~ /\A ([^.]*) /x) {
        return $self->can("__${page_id}__$1");
    }

    return;
}

sub end {
    my ($self, @args) = @_;
    return @args;
}

my @EMPTY;
sub get_values {
    my ($self, $key, @i) = @_;
    return @{ $self->Waft::_value->{$key} || \@EMPTY }[@i] if @i;
    return @{ $self->Waft::_value->{$key} || \@EMPTY };
}

sub get_value {
    my ($self, $key, @i) = @_;
    return( ( $self->get_values($key, @i) )[0] );
}

{
    # deprecated methods

    sub __DEFAULT {
        my ($self, @args) = @_;
        return ['default.html', $self->action], @args;
    }

    *add_header = *add_header = \&header;

    sub array {
        my ($self, $key, @values) = @_;

        if (@values) {
            my @old_values = $self->get_values($key);
            $self->set_values($key, @values);
            return @old_values;
        }

        return $self->get_values($key);
    }

    sub arrayref {
        my ($self, $key, $arrayref) = @_;

        return $self->Waft::_value->{$key} = $arrayref
            if ref $arrayref eq 'ARRAY';

        return $self->Waft::_value->{$key} ||= [];
    }

    *call_template = *call_template = \&include;

    sub form_elements {
        my ($self, @args) = @_;

        if (@args == 1
            and defined $args[0]
            and $args[0] eq 'ALL' || $args[0] eq 'ALLVALUES'
        ) {
            $args[0] = 'ALL_VALUES';
        }

        $self->output_waft_tags(@args);

        return;
    }

    *_join_values = \&join_values;
}

package Waft::Object;

use Carp;
use English qw( -no_match_vars );

sub TIEHASH {
    bless {};
}

sub STORE {
    if (ref $_[2] eq 'ARRAY') {
        @{ $_[0]{defined $_[1] ? $_[1] : _undef()} } = @{$_[2]};
    }
    else {
        @{ $_[0]{defined $_[1] ? $_[1] : _undef()} } = ($_[2]);
    }
}

sub _undef () {
    if ($WARNING) {
        carp 'Use of uninitialized value';
    }

    return q{};
}

sub FETCH {
    my $arrayref = $_[0]{defined $_[1] ? $_[1] : _undef()}
        or return;

    $arrayref->[0];
}

sub FIRSTKEY { keys %{$_[0]}; each %{$_[0]} }

sub NEXTKEY  {                each %{$_[0]} }

sub EXISTS { exists $_[0]{defined $_[1] ? $_[1] : _undef()} }

sub DELETE { delete $_[0]{defined $_[1] ? $_[1] : _undef()} }

sub CLEAR { %{$_[0]} = () }

1;
__END__

=head1 NAME

Waft - A simple web application framework

=head1 SYNOPSIS

    ==========================================================================
    myform.cgi
    --------------------------------------------------------------------------
    #!/usr/bin/perl
    use lib 'lib';
    require MyForm;
    MyForm->waft;

    ==========================================================================
    lib/MyForm.pm
    --------------------------------------------------------------------------
    package MyForm;

    use base 'Waft';

    sub __default__direct {
        my ($self) = @_;

        $self->{name} = q{};
        $self->{address} = q{};
        $self->{phone} = q{};
        $self->{comment} = q{};

        return 'TEMPLATE';
    }

    sub __default__submit {
        my ($self) = @_;

        $self->{name} = $self->query->param('name');
        $self->{address} = $self->query->param('address');
        $self->{phone} = $self->query->param('phone');
        $self->{comment} = $self->query->param('comment');

        return 'confirm.html';
    }

    sub __confirm__indirect {
        my ($self) = @_;

        return 'default.html', 'error!' if length $self->{name} == 0;

        return 'TEMPLATE';
    }

    sub __confirm__submit {
        return 'thankyou.html';
    }

    sub __confirm__back {
        return 'default.html';
    }

    sub __thankyou__indirect {
        my ($self) = @_;

        open my $fh, '>> form.log';
        print {$fh} $self->{name}, "\n";
        print {$fh} $self->{address}, "\n";
        print {$fh} $self->{phone}, "\n";
        print {$fh} $self->{comment}, "\n";
        close $fh;

        return 'TEMPLATE';
    }

    1;

    ==========================================================================
    lib/MyForm.template/default.html
    --------------------------------------------------------------------------
    <%
    my ($self, $error) = @_;
    %>
    <html>

    <head>
        <title>FORM</title>
    </head>

    <body>
        <% if ($error) { %>
            <p>
            <% = $error %>
            </p>
        <% } %>

        <form action="<% = $self->url %>" method="POST">

        <p>
        Name:
        <input type="text" name="name" value="<% = $self->{name} %>" />
        </p>

        <p>
        Address:
        <input type="text" name="address" value="<% = $self->{address} %>" />
        </p>

        <p>
        Phone:
        <input type="text" name="phone" value="<% = $self->{phone} %>" />
        </p>

        <p>
        Comment: <br />
        <textarea name="comment"><% = $self->{comment} %></textarea>
        </p>

        <p>
        <input type="submit" />
        </p>

        </form>
    </body>

    </html>

    ==========================================================================
    lib/MyForm.template/confirm.html
    --------------------------------------------------------------------------
    <%
    my ($self) = @_;
    %>
    <html>

    <head>
        <title>FORM - CONFIRM</title>
    </head>

    <body>
        <form action="<% = $self->url %>" method="POST">

        <p>
        Name: <% = $self->{name} %>
        </p>

        <p>
        Address: <% = $self->{address} %>
        </p>

        <p>
        Phone: <% = $self->{phone} %>
        </p>

        <p>
        Comment: <br />
        <% text = $self->{comment} %>
        </p>

        <p>
        <input type="submit" />
        <input type="submit" name="back" value="back to FORM" />
        </p>

        </form>
    </body>

    </html>

    ==========================================================================
    lib/MyForm.template/thankyou.html
    --------------------------------------------------------------------------
    <%
    my ($self) = @_;
    %>
    <html>

    <head>
        <title>FORM - THANKYOU</title>
    </head>

    <body>
        <p>
        Thank you for your comment!
        </p>

        <p>
        Name: <% = $self->{name} %>
        </p>

        <p>
        Address: <% = $self->{address} %>
        </p>

        <p>
        Phone: <% = $self->{phone} %>
        </p>

        <p>
        Comment: <br />
        <% text = $self->{comment} %>
        </p>
    </body>

    </html>

=head1 AUTHOR

Yuji Tamashiro, E<lt>yuji@tamashiro.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Yuji Tamashiro

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
