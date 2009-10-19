#!/usr/bin/env perl
use warnings;
use strict;

use Test::More tests => 5;

eval q{
    package A;
    use namespace::clean -except;
};
like $@, qr/-except/, 'missing arguments for import -except';

eval q{
    package A;
    use namespace::clean -cleanee;
};
like $@, qr/-cleanee/, 'missing arguments for import -cleanee';

eval q{
    package A;
    use namespace::clean -foo;
};
like $@, qr/import/, 'wrong arguments for import';

eval q{
    package A;
    no namespace::clean -cleanee;
};
like $@, qr/-cleanee/, 'missing arguments for unimport -cleanee';

eval q{
    package A;
    no namespace::clean -foo;
};
like $@, qr/unimport/, 'wrong arguments for unimport';
