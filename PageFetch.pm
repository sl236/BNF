# License: Creative Commons Attribution-ShareAlike 4.0, http://creativecommons.org/licenses/by-sa/4.0/
# Creator repo: https://github.com/sl236/BNF

package PageFetch;
$VERSION='1.0';
use strict;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT=qw(FetchPageText FetchRawPageText);

local $| = 1;  # Do not buffer output (localized for mod_perl)

# Configuration/constant variables:
use vars qw(
  $DataDir $PageDir
  $UseSubpage $SimpleLinks $NonEnglish $FreeUpper 
  $FreeLinkPattern $LinkPattern
  $BNFLinkPattern $MTGLinkPattern
  $FS $FS1 $FS2 $FS3 
  $FreeLinks $WikiLinks 
  );

use vars qw(%Page %Section %Text
  %KeptRevisions %IndexHash
  %LinkIndex $MainPage
  $OpenPageName @KeptList @IndexList $IndexInit
  );

# == Configuration =====================================================
# Default configuration (used if UseConfig is 0)

# Major options:
$FreeLinks   = 1;       # 1 = use [[word]] links, 0 = LinkPattern only
$WikiLinks   = 1;       # 1 = use LinkPattern,    0 = use [[word]] only

# Minor options:
$UseSubpage = 1;
$SimpleLinks = 0;       # 1 = only letters,       0 = allow _ and numbers
$NonEnglish  = 0;       # 1 = extra link chars,   0 = only A-Za-z chars
$FreeUpper   = 1;       # 1 = force upper case,   0 = do not force case

# ---------------------------------
my @HtmlSingle = qw( br hr );
my @HtmlPairs = qw( b i h1 h2 h3 blockquote pre table td tr thead tbody );

sub T{
return $_[0];
}

sub InitLinkPatterns {
  my ($UpperLetter, $LowerLetter, $AnyLetter, $LpA, $LpB, $QDelim);

  # Field separators are used in the URL-style patterns below.
  $FS  = "\xb3";      # The FS character is a superscript "3"
  $FS1 = $FS . "1";   # The FS values are used to separate fields
  $FS2 = $FS . "2";   # in stored hashtables and other data structures.
  $FS3 = $FS . "3";   # The FS character is not allowed in user data.

  $OpenPageName = undef;

  $UpperLetter = "[A-Z";
  $LowerLetter = "[a-z";
  $AnyLetter   = "[A-Za-z";
  if ($NonEnglish) {
    $UpperLetter .= "\xc0-\xde";
    $LowerLetter .= "\xdf-\xff";
    $AnyLetter   .= "\xc0-\xff";
  }
  if (!$SimpleLinks) {
    $AnyLetter .= "_0-9";
  }
  $UpperLetter .= "-]"; $LowerLetter .= "-]"; $AnyLetter .= "-]";

  # Main link pattern: lowercase between uppercase, then anything
  $LpA = $UpperLetter . "+" . $AnyLetter . "*";
  # Optional subpage link pattern: uppercase, lowercase, then anything
  $LpB = $UpperLetter . "+" . $AnyLetter . "*";

  # #search_in_page
  my $LpC = "#[a-zA-Z0-9_]+";

    # Loose pattern: If subpage is used, subpage may be simple name
    $LinkPattern = "((?:(?:(?:$LpB)?\\/$LpB)|$LpA)(?:$LpC)?)";
    # Strict pattern: both sides must be the main LinkPattern
    # $LinkPattern = "((?:(?:$LpA)?\\/)?$LpA)";
  $QDelim = '(?:"")?';     # Optional quote delimiter (not in output)
  $LinkPattern .= $QDelim;

  if ($FreeLinks) {
    # Note: the - character must be first in $AnyLetter definition
    if ($NonEnglish) {
      $AnyLetter = "[-,.()' _0-9A-Za-z\xc0-\xff]";
    } else {
      $AnyLetter = "[-,.()' _0-9A-Za-z]";
    }
  }
  $FreeLinkPattern = "($AnyLetter+)";
  if ($UseSubpage) {
    $FreeLinkPattern = "((?:(?:$AnyLetter+)?\\/)?$AnyLetter+)";
  }
  $FreeLinkPattern .= $QDelim;
  $BNFLinkPattern = "BNF:" . $LinkPattern;
  $MTGLinkPattern = "MTG:([A-Za-z0-9+-]+)";
}

sub FreeToNormal_ {
  my ($id) = @_;

  $id =~ s/ /_/g;
  $id = ucfirst($id);
  if (index($id, '_') > -1) {  # Quick check for any space/underscores
    $id =~ s/__+/_/g;
    $id =~ s/^_//;
    $id =~ s/_$//;
    if ($UseSubpage) {
      $id =~ s|_/|/|g;
      $id =~ s|/_|/|g;
    }
  }
  if ($FreeUpper) {
    # Note that letters after ' are *not* capitalized
    if ($id =~ m|[-_.,\(\)/][a-z]|) {    # Quick check for non-canonical case
      $id =~ s|([-_.,\(\)/])([a-z])|$1 . uc($2)|ge;
    }
  }
  return $id;
}

sub OpenSection {
  my ($name) = @_;

  if (!defined($Page{$name})) {
    $OpenPageName = 0;
  } else {
    %Section = split(/$FS2/, $Page{$name}, -1);
  }
}

sub OpenText {
  my ($name) = @_;

  if (!defined($Page{"text_$name"})) {
    $OpenPageName = 0;
  } else {
    &OpenSection("text_$name");
    %Text = split(/$FS3/, $Section{'data'}, -1);
  }
}

sub GetPageDirectory {
  my ($id) = @_;

  if ($id =~ /^([a-zA-Z])/) {
    return uc($1);
  }
  return "other";
}

sub GetPageFile {
  my ($id) = @_;

  return $PageDir . "/" . &GetPageDirectory($id) . "/$id.db";
}

sub OpenPage {
  my ($id) = @_;
  my ($fname, $data);

  # if (defined $OpenPageName && ($OpenPageName eq $id)) {
  #   return;
  # }
  $OpenPageName = 0;
  %Section = ();
  %Text = ();
  $fname = &GetPageFile($id);
  if (-f $fname) {
    $data = &ReadFile($fname);
    %Page = split(/$FS1/, $data, -1);  # -1 keeps trailing null fields
	$OpenPageName = $id;
  }
}

sub ReadFile {
  my ($fileName) = @_;
  my ($data);
  local $/ = undef;   # Read complete files

  if (open(IN, "<$fileName")) {
    $data=<IN>;
    close IN;
    return $data;
  }

  $OpenPageName = 0;
  return "";
}

sub QuoteHtml {
  my ($html) = @_;

  $html =~ s/&/&amp;/g;
  $html =~ s/</&lt;/g;
  $html =~ s/>/&gt;/g;
  if (1) {   # Make an official option?
    $html =~ s/&amp;([#a-zA-Z0-9]+);/&$1;/g;  # Allow character references
  }
      my $t;
      foreach $t (@HtmlPairs) {
        $html =~ s/\&lt;$t((?:\s[^<>]+?)?)\&gt;(.*?)\&lt;\/$t\&gt;/<$t$1>$2<\/$t>/gis;
      }

      foreach $t (@HtmlSingle) {
        # $html =~ s/\&lt;$t(\s[^<>]+?)\&gt;/<$t$1>/gi;
        $html =~ s/\&lt;$t\s+\/\&gt;/<$t \/>/gi;
        $html =~ s/\&lt;$t\&gt;/<$t>/gi;
      }
      my $Wiki = "http://www.toothycat.net/wiki/wiki.pl?";
       my $BNF="http://www.toothycat.net/wiki/bnf.pl?page=";
       my $MTG="http://www.wizards.com/magic/autocard.asp?name=";
      $html =~ s/\[$FreeLinkPattern\s+([^\]]+?)\]/&StoreBracketLink($1, $2, $Wiki)/geos;
      $html =~ s/\[$BNFLinkPattern\s+([^\]]+?)\]/&StoreBracketLink($1, $2, $BNF)/geos;
      $html =~ s/$MTGLinkPattern/&StoreLink($1, 'MTG: ' . $1, $MTG)/geos;

  return $html;
}

sub StoreLink
{
my ($id, $name, $url) = @_;
  $id =~ s/[@"]//g;
  $url =~ s/[@"]//g;
 $name =~ s/[+]/ /g;
  return "<a href=\"$url$id\">$name</a>";
}

sub StoreBracketLink
{
  my ($id, $name, $url) = @_;

  {
    $id = &FreeToNormal($id);
    $name =~ s/_/ /g;
  }

  return "<a href=\"$url$id\">$name</a>";
}

sub FreeToNormal {
  my ($id) = @_;

  $id =~ s/ /_/g;
  $id = ucfirst($id);
  if (index($id, '_') > -1) {  # Quick check for any space/underscores
    $id =~ s/__+/_/g;
    $id =~ s/^_//;
    $id =~ s/_$//;
    
      $id =~ s|_/|/|g;
      $id =~ s|/_|/|g;
  }
  {
    # Note that letters after ' are *not* capitalized
    if ($id =~ m|[-_.,\(\)/][a-z]|) {    # Quick check for non-canonical case
      $id =~ s|([-_.,\(\)/])([a-z])|$1 . uc($2)|ge;
    }
  }
  return $id;
}



sub FetchPageText
{
  my($dir, $query) = @_;
  $DataDir = $dir;
  $PageDir     = "$DataDir/page";
  &InitLinkPatterns();

  if (!($query =~ /^$FreeLinkPattern$/)) 
  {
		return "$query: not a valid (/^$FreeLinkPattern$/) page name.";
  }

  &OpenPage($query);
  &OpenText('default');
  defined $Text{'text'} and $Text{'text'} =~ s/<\/?nowiki>//gi;
  defined $Text{'text'} and $Text{'text'} =~ s/<\/?pre>//gi;
  defined $Text{'text'} and $Text{'text'} =~ s/(<\/?)(aa)>/$1pre>/gi;

  if(!$OpenPageName)
  {
    return "Invalid or unreified page.";
  }

  return QuoteHtml($Text{'text'});
}

sub FetchRawPageText
{
  my($dir, $query) = @_;
  $DataDir = $dir;
  $PageDir     = "$DataDir/page";
  &InitLinkPatterns();

  if (!($query =~ /^$LinkPattern$/)) 
  {
    if (!($FreeLinks && ($query =~ /^$FreeLinkPattern$/))) 
	{
		return "Not a valid page name.";
	}
  }

  &OpenPage($query);
  &OpenText('default');

  if(!$OpenPageName)
  {
    return "Invalid or unreified page.";
  }

  return $Text{'text'};
}


# ---------------------------------
1;
