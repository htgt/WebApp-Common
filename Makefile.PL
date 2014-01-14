
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Common code shared between LIMS2 and WGE",
  "AUTHOR" => "Wellcome Trust Sanger Institute",
  "BUILD_REQUIRES" => {
    "Class::Data::Inheritable" => 0,
    "English" => 0,
    "File::Find" => 0,
    "File::Temp" => 0,
    "FindBin" => 0,
    "Test::Class" => 0,
    "Test::More" => "0.88",
    "Test::Most" => 0,
    "base" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "WebAppCommon",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "WebAppCommon",
  "PREREQ_PM" => {
    "Bio::EnsEMBL::Registry" => 0,
    "Data::UUID" => 0,
    "Hash::MoreUtils" => 0,
    "JSON" => 0,
    "LIMS2::Util::FarmJobRunner" => 0,
    "List::MoreUtils" => 0,
    "Moose" => 0,
    "Moose::Role" => 0,
    "MooseX::ClassAttribute" => 0,
    "namespace::autoclean" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.001",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



