#!perl -w

use strict;
use Benchmark qw(:all);

require Mouse;
require Mouse::Util::TypeConstraints;

print "no cleaning v.s. use namespace::clean\n";
cmpthese -1 => {
    use_mouse => sub{
        eval q{
            package X1;
            use Mouse;
        };
        die $@ if $@;
    },
    use_nsc => sub{
        eval q{
            package Y1;
            use Mouse;
            use namespace::clean -except => 'meta';
        };
        die $@ if $@;
    },
};

print "no Mouse v.s. use namespace::clean\n";
cmpthese -1 => {
    no_mouse => sub{
        eval q{
            package X1;
            use Mouse;

            no Mouse;
        };
        die $@ if $@;
    },
    use_nsc => sub{
        eval q{
            package Y1;
            use Mouse;
            use namespace::clean -except => 'meta';
        };
        die $@ if $@;
    },
};

print "no Mouse && no Mouse::Util::TypeConstraints v.s. use namespace::clean\n";
cmpthese -1 => {
    no_mouse => sub{
        eval q{
            package X2;
            use Mouse;
            use Mouse::Util::TypeConstraints;

            no Mouse;
            no Mouse::Util::TypeConstraints;
        };
        die $@ if $@;
    },
    use_nsc => sub{
        eval q{
            package Y2;
            use Mouse;
            use Mouse::Util::TypeConstraints;
            use namespace::clean -except => 'meta';
        };
        die $@ if $@;
    },
};

