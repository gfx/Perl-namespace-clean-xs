#!perl -w

package A;
use strict;
use Mouse;

use namespace::clean -except => 'meta';

use Data::Dumper;

no namespace::clean;

use Carp;

use namespace::clean;

print Dumper(namespace::clean->get_class_store('A'));
