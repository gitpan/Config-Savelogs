use 5.008001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Config::Savelogs',
    VERSION_FROM      => 'lib/Config/Savelogs.pm', # finds $VERSION
    PREREQ_PM         => { Storable => 1.014 },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Config/Savelogs.pm', # retrieve abstract from module
       AUTHOR         => 'Scott Wiersdorf <scott@perlcode.org>') : ()),
);
