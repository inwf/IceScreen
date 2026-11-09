use strict;
use warnings;
use DynaLoader;

my ($library) = @ARGV;
die "Missing media bridge library\n" unless defined $library && -f $library;
my $handle = DynaLoader::dl_load_file($library, 0)
    or die DynaLoader::dl_error();
my $entry = DynaLoader::dl_find_symbol($handle, "IceScreenMediaMain")
    or die DynaLoader::dl_error();
DynaLoader::dl_install_xsub("IceScreen::run", $entry);
IceScreen::run();
