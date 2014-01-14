#!/usr/bin/env perl
use inc::Module::Install 1.02;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'WebAppCommon';
all_from 'lib/WebAppCommon.pm';

requires 'Moose';
requires 'namespace::autoclean';
test_requires 'Test::More' => '0.88';
catalyst;

auto_install;
WriteAll;
