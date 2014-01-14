#!/usr/bin/env perl
use inc::Module::Install 1.02;
# using this subclass because it grabs all the folders in root and installs them.
# we need this to install the shared_templates folder
use Module::Install::Catalyst;

name 'WebAppCommon';
all_from 'lib/WebAppCommon.pm';

requires 'Moose';
requires 'namespace::autoclean';
test_requires 'Test::More' => '0.88';
catalyst;

auto_install;
WriteAll;
