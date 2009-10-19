use strict;
use warnings;
use inc::Module::Install;

BEGIN{ # for co-developers
    require Module::Install::AuthorTests;
    require Module::Install::XSUtil;
}

all_from 'lib/namespace/clean.pm';

use_ppport 3.19;
cc_warnings;

test_requires 'Test::More' => 0.88;

tests 't/*.t';
author_tests 'xt';

auto_set_repository() if -d '.git';

clean_files qw(
	namespace-clean-* *.stackdump
	*.gcda *.gcno *.gcov
	nytprof *.out
	cover_db
);

WriteAll check_nmake => 0;

