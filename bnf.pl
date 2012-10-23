#!/usr/bin/speedy -w -- -gwiki -M5 -r30
use strict;
use CGI;
use PageFetch;

use vars qw($maxiter $maxlen %options %includes %tags $validtag $commandchar);

sub ResetGlobals
{
	# hard options
	$maxiter = 16000; # maximum number of tags to resolve before giving up
	$maxlen = 64000; # maximum length of generated string

	# defaults for mutable options
	%options = 
	(
	  'spaces' => 1,   # put spaces between elements
	  'debug' => 0,    # generate debug trace
	  'evil' => 0      # append Google ad
	);

	%includes = ( );

	# bnf syntax
	# name ::= |-separated-list of list of name or string or "string"
	# root tag is bnf

	# implemented as hash of array of array

	%tags = ( );
	$validtag = qw/(?:(?:(?:&lt;)[A-Za-z0-9_-]+?(?:&gt;))|(?:[A-Za-z0-9_-]+))/;
	$commandchar = '!';
	# commandchar must be a character that's not legal at the start of tag names (i.e. not present in $validtag)
}

sub parseBnfLine
{
  my ($line) = @_;

  $line =~ /^ *($validtag) *::= *(.*) *$/ or return;

  my $name = $1;
  $line = $2;

  if($name eq 'option')
  {
    if($line =~ /([A-Za-z_]+) *= *([^ ]+)/)
	{
	  $options{$1} = $2;
	}
  }

  my $sequences = [ ];
  my $curr_sequence = [ ];

  while(length $line > 0)
  {
    $line =~ s/^ *//; # strip leading spaces
	if($line =~ /^(\".*?[^\\]\")(.*)/)
	{
      # we have a quoted string as the next symbol
	  my $symbol = $1;
	  $line = $2;
	  $symbol =~ s/\\(.)/$1/g;
	  push @$curr_sequence, $symbol;
	}
	else
	{
	  my $symbol = $line;
	  if($line =~ /^([^ ]+) (.*)$/)
	  {
	    $symbol = $1;
		$line = $2;
	  }
	  else
	  {
	    $line = '';
	  }
	  $symbol =~ s/\\(.)/$1/g;

	  if($symbol eq "|")
	  { 
		if($#$curr_sequence >= 0)
		{
	     push @$sequences, $curr_sequence;
		 $curr_sequence = [ ];
		}
	  }
	  else
	  {
        if($symbol =~ /^$commandchar/)
        {
            # they're starting a symbol with an unquoted command char
            # we can't have that: quote it
            # we know there's no bad effects to this because commandchar
            # is not legal in tag names
            $symbol = '"' . $symbol . '"';
        }
	    push @$curr_sequence, $symbol;
	  }
	}
  }
 
  if($#$curr_sequence >= 0)
  {
   push @$sequences, $curr_sequence;
  }

  $tags{$name} = $sequences;
}

sub dumpBNF
{
  foreach my $k (keys %tags)
  {
    print "$k ::= ";
	my $i = -1;
	while(++$i < $#{$tags{$k}})
	{
	  my $seq = $tags{$k}->[$i];
	  foreach my $item(@$seq)
	  {
            my $titem = $item;
	    if($titem =~ / /)
		{
		 $titem = '"' . $titem . '"';
		}
	    print "$titem ";
	  }
	  print "| ";
	}

	{
	  my $seq = $tags{$k}->[$#{$tags{$k}}];
	  foreach my $item(@$seq)
	  {
            my $titem = $item;
	    if($titem =~ / /)
		{
		 $titem = '"' . $titem . '"';
		}
	    print "$titem ";
	  }
	}
	print "<BR>\n";
  }
  print "<BR>\n";
}

sub resolveConcats
{
   my ($tag) = @_;

   while($tag =~ /^($validtag)\#\#($validtag)(.*?)$/)
   {
     my $root = $1;
     my $ccat = $2;
     my $rest = '';
     if(defined($3))
     {
       $rest = $3;
     }
     $options{'debug'} and print '<i>Concatenation:</i> '. $tag . 
           #' (' . $root . ',' . $ccat . ',' . $rest . ')' . 
           ' --> ';
     if(
        defined($tags{$ccat}) && 
        ($#{$tags{$ccat}} == 0) && 
        ($#{$tags{$ccat}->[0]} == 0) &&
        ($tags{$ccat}->[0][0] =~/^$validtag$/)
       )
     {
       $tag = $root . '_' . $tags{$ccat}->[0][0] . $rest;
     }
     else
     {
       $tag = $root . '_' . $ccat . $rest;
     }
     $options{'debug'} and print $tag;
     $options{'debug'} and print " <BR>\n";
   }    
   return $tag;
}

sub generateString
{
  my @results = ( '' );
  my @unresolved = ( "bnf" );
  my $iter = 0;

  while($#unresolved >= 0)
  {
    my $tag = shift @unresolved;
    my $silent = '';
    my $iterresult = [ ];
    my @postassign = ( );
# -------- note silent assigns and postfix assigns 
    if($tag =~ /^&lt;($validtag(?:\#\#$validtag)*)::=($validtag(?:\#\#$validtag)*)&gt;$/)
    {
      # silent assign
      $silent = resolveConcats($1);
      $tag = $2;
    }
    elsif($tag =~ /^&lt;($validtag(?:\#\#$validtag)*)::=("[^"]*")&gt;$/)
    {
      # quoted silent assign
      $silent = resolveConcats($1);
      $tag = $2;
    }
    elsif($tag =~ /^&lt;&lt;($validtag(?:\#\#$validtag)*)::=($validtag(?:\#\#$validtag)*)&gt;&gt;$/)
    {
      # deep silent assign
      $tag = $2;
      my $deepname = resolveConcats($1);
      $options{'debug'} and print "Start deep calculation of $tag to assign to $deepname<BR>\n";
      my $ctag = $commandchar . 'deepname' . ' ' . $deepname;
      unshift @unresolved, $ctag; 
      unshift @results, '';      
    }
   
    $tag =~ /^".*"$/ or $tag = resolveConcats($tag);
  
    # do we have any postfix assigns?
    while($tag =~ /^($validtag){($validtag(?:\#\#$validtag)*)}(.*)$/ or $tag =~ /^($validtag){{($validtag(?:\#\#$validtag)*)}}(.*)$/)
    {
      if ($tag =~ /^($validtag){($validtag(?:\#\#$validtag)*)}(.*)$/)
      {
        # shallow postfix assign
        push @postassign, $2; 
        $tag = $1;
        defined($3) and $tag = $tag . $3;
      }
      elsif ($tag =~ /^($validtag){{($validtag(?:\#\#$validtag)*)}}(.*)$/)
      {
        # deep postfix assign
        # because we only want to output to one result at once, convert this
        # from  foo{{bar}}  to  <<bar::=foo>> bar
        $options{'debug'} and print "Start deep calculation of $1 to assign to $2<BR>\n";
        unshift @unresolved, $2;     # prepend a bar
        my $ctag = $commandchar . 'deepname' . ' ' . $2;
        unshift @unresolved, $ctag;  # then prepend the command to assign to bar
        unshift @results, '';      
        $tag = $1;
        defined($3) and $tag = $tag . $3;
      }
    }

# -------- Resolve the tag

	if (($iter++ > $maxiter) || (length($results[$#results]) > $maxlen))
	{
	  return $results[0] . "<BR>(...)";
	}
        $options{'debug'} and print "Iteration $iter: ";
	
    if ( $tag =~ /^($commandchar)/ )
    {
        # this is a command
        #print "Found command '$tag'! ";
        if ( $tag =~ /^($commandchar)deepname (.*)$/ )
        {
			# we've completed a deep assign
			my $deepassignvar = shift(@results);
			# all the tags come out of a deep assign flattened into a string,
			# so we have to wrap them twice in []s to get the required array of arrays
			$tags{$2} = [ [ $deepassignvar ] ];
			if($options{'debug'})
			{
				print 'Deep assign: (' . $2 . '::=' . $deepassignvar . ")<br>\n";
			}
        }
    }
    elsif( $tags{$tag} )
	{
	  # select a possible sequence at random
	  my $index = int( rand( $#{$tags{$tag}} + 1 ) );
          defined $index or $index = 0;

	  # add the items in the sequence to the unresolved list
	  if($options{'debug'})
          {
            print "<i>Lookup:</i> $tag ::=";
	    foreach my $item(@{${$tags{$tag}}[$index]})
	    {
	      print " $item";
	    }
	    print "<BR>\n";
	  }
	  if(defined(${$tags{$tag}}[$index])) 
	  {
	   foreach my $item(reverse @{${$tags{$tag}}[$index]})
	   {
            if($silent eq '')
            {
	      unshift @unresolved, $item;
            }
            unshift @$iterresult, $item;
	   }
	  }
	}
	else
	{
          my $ttag = $tag;
	  $ttag =~ s/^"(.*)"$/$1/;

          if($silent eq '')
          {
	    if( ((length($results[0])>0) && (length($ttag)>0) && ($options{'spaces'})) )
	    {
	      $results[0] .= " ";
	    }
	    $results[0] .= $ttag;
          }
          push @$iterresult, $tag;
	}
 
        if($silent ne '')
        {
          if($options{'debug'})
          {
           print '<i>Silent assign:</i> (' . $silent . '::=' ;
           foreach my $item(@$iterresult )
           {
            print $item; 
           }
           print ")<BR>\n";
          }
          $tags{$silent} = [ $iterresult ];
        }
        # else
        {
          foreach my $item(@postassign)
          {
           if($options{'debug'})
           {
            print '<i>Postfix assign:</i> {' . $item . '::=' ;
            foreach my $i(@$iterresult )
            {
             print $i; 
            }
            print "}<BR>\n";
           }
            $tags{$item} = [ $iterresult ];
          }
        }
  }

  return $results[0];
}

sub WikiLink
{
  my ($name) = @_;
  return '<A HREF="http://www.toothycat.net/wiki/wiki.pl?' . 
		$name . '">' . $name . '</A>';
}

sub main()
{
 ResetGlobals();
 srand();
 my $seed = int(rand()*(1<<31));
 my $q = new CGI;
 print $q->header, $q->start_html("BNF generator");

 my $s = $q->param('seed'); 
 if(defined($s) && ($s =~ /([0-9-]+)/))
 {
   $seed = $1;
 }

 print '<!-- Seed: ' . $seed . ' -->'."\n";
 srand($seed);

 if(defined($q->param('page')))
 {
    my @text = split(/[\r\n]/, FetchPageText('/home/sham/root/wiki/data', 
       $q->param('page')));
    
	while($#text>-1)
	{
            my $item = shift @text;
	    $item =~ /[^ ]/ or next;
            $options{'include'} = 0;
		&parseBnfLine($item);
            if($options{'include'} && !defined($includes{$options{'include'}}))
            {
              my @newtext = split(/[\r\n]/, 
             FetchPageText('/home/sham/root/wiki/data', $options{'include'})); 
              @text = (@newtext, @text);
              $includes{$options{'include'}} = 1;
            }
	}

 if(defined($q->param('debug')))
 {
   $options{'debug'} = 1;
 }

	if(defined $tags{"bnf"}) # success
	{
		$options{'debug'} and print '<B>Here, in no particular order, are the rules I found:</B><BR>';
		$options{'debug'} and &dumpBNF();
		$options{'debug'} and print '<BR><HR>';
		$options{'debug'} and print '<B>This is what I did with them:</B><BR>';
		my $result =  &generateString();
		$options{'debug'} and print '<BR><HR>';
		$options{'debug'} and print '<B>..and here\'s what I got:</B><BR>';
                print $result;
		print '<BR><HR>';
		print &WikiLink($q->param('page'));
	}
	else
	{
	    print 'No "bnf" tag was found. See ' . &WikiLink("MoonShadow/GeneratorGenerator") . ' for more details.<BR>';
            #print join("<BR>", @text);
	}
 }
 else
 {
   print 'Invoke using a link to http://www.toothycat.net/wiki/bnf.pl?page=<I>HomePage/SubPageName</I>. See ' . &WikiLink("MoonShadow/GeneratorGenerator") . ' for more details.'; 
 }

 if( $options{'evil'} )
 {
print <<'AD'
<div style="float: right">
<script type="text/javascript"><!--
google_ad_client = "pub-3160732673995309";
google_ad_width = 234;
google_ad_height = 60;
google_ad_format = "234x60_as";
google_ad_type = "text";
google_ad_channel ="";
google_color_border = "EEEEEE";
google_color_bg = "FFFFFF";
google_color_link = "AAAAAA";
google_color_url = "CCCCCC";
google_color_text = "999999";
//--></script>
<script type="text/javascript"
src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>
</div>
AD
;
 }

 print $q->end_html; 
}

&main();

