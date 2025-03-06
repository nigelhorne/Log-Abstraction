use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Log::YetAnother',
    VERSION_FROM => 'Log::YetAnother.pm', # finds $VERSION
    AUTHOR       => 'Nigel Horne <njh@nigelhorne.com>',
    ABSTRACT     => 'A flexible logging class for Perl',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Carp'        => 0,
        'Params::Get' => 0,
        'Sys::Syslog' => 0,
        'Scalar::Util'=> 0,
    },
    TEST_REQUIRES => {
        'Test::More'  => 0,
        'Test::Most'  => 0,
        'File::Temp'  => 0,
    },
    META_MERGE => {
        resources => {
            repository => {
                type => 'git',
                url  => 'git://github.com/nigelhorne/log-yetanother.git',
                web  => 'https://github.com/nigelhorne/log-yetanother',
            },
        },
    },
);
