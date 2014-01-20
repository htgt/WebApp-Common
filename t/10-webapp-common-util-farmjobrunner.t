#!/usr/bin/env perl
use strict;
use warnings FATAL => 'all';

use FindBin;
use lib "$FindBin::Bin/lib";
use WebAppCommon::Test::Util::FarmJobRunner;

Test::Class->runtests;
