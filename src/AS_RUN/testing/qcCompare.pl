#!/usr/bin/env perl
#
###########################################################################
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received (LICENSE.txt) a copy of the GNU General Public 
# License along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
###########################################################################
#
# $Id: qcCompare.pl,v 1.4 2005-12-16 22:12:38 catmandew Exp $
#

# Program to compare an arbitrary number of qc files generated by caqc
#
# Algo:
#   Parsing qc file
#   If line begins with '[' character, it begins a category and
#     category name is string between '[' and ']'
#   If category line has '=' in it,
#     what precedes the what follows the '=' is the category name
#     what follows is a comma-delimited list of field names
#   Non-blank, non-category lines have format:
#     varname=value  or
#     itemNum=value1,value2,value3,... for categories with fields
#     Total=value1,value2, value3,... as total for categories with fields
#
#   So, store contents of each file in hashtable
#     key = category (keep "=" for multi-field categories)
#     value = hash of
#       key = varname or itemNum
#       value = value or hash of
#         key = field name
#         value = value
#
#   Comarison:
#   Iterate over category keys in file1 data
#     make sure no categories are missing in file2
#     Iterate over keys: varNames or itemNums
#
#         compare values in file1 and file2 data
#       if category ends in "="
#         value is hashtable
#         check that file1 data & file2 data have same number of keys
#           in this category
#         iterate over keys (field names)
#           compare values
#
#   Comparison should be absolute & pct
#   Print out only differences
#       
#
#   Written by Ian Dew
#

use Carp;
use strict;
use FileHandle;
use Getopt::Long;

my $MY_VERSION = " Version 1.01 (Build " . (qw/$Revision: 1.4 $/ )[1]. ")";
my $MY_APPLICATION = "qcCompare";

my $HELPTEXT = qq~
Compare two caqc-generated qc files

    qcCompare  [options]  -f file1 -f file2 ...

    -f file1       The 'reference' qc filename

    -f file2       The first 'query' qc filename
                     An arbitrary number of query filenames may be specified
  
    options:
      -h               Print help.
  
      -v <level>       Set verbosity to level.

$MY_VERSION

~;


######################################################################
# Parse the command line
######################################################################
my $helpRequested;
my $verboseLevel = 0;
my @files;

GetOptions("f=s" => \@files,
           "h|help" => \$helpRequested,
           "v|V|verbose:1" => \$verboseLevel
           ) or die $HELPTEXT;

if($helpRequested)
{
  print STDERR "Help requested:\n\n";
  print STDERR $HELPTEXT;
  exit 0;
}

if($#files < 1)
{
  print STDERR "Please specify two or more qc files\n\n";
  print STDERR $HELPTEXT;
  exit 1;
}

for(my $i = 0; $i <= $#files; $i++)
{
  if(! -f $files[$i])
  {
    print STDERR "%s is not a file!\n", $files[$i];
    print STDERR $HELPTEXT;
    exit 1;
  }
}


######################################################################
# Read in files
######################################################################
# array of hashes containing stats from each file
my $fdata = [];
# array to maintain the order of stats listed in the reference file
my @rlist;
for(my $i = 0; $i <= $#files; $i++)
{
  %{$fdata->[$i]} = ReadQCFile($files[$i]);
}

if($verboseLevel)
{
  for(my $i = 0; $i <= $#files; $i++)
  {
    PrintQCFile(\%{$fdata->[$i]});
  }
}

######################################################################
# Compare qc data
######################################################################
my $printedHeader = 0;
my $header = "Category Entry(-Field)\tRef#\tQuery#\tDelta#\tDelta\%";

my %f1data = %{$fdata->[0]};

# iterate over non-reference qc files
for(my $i = 1; $i <= $#files; $i++)
{
  my %f2data = %{$fdata->[$i]};

  printf "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n";
  printf "Reference QC File: %s\n", $files[0];
  printf "Query QC File:     %s\n\n", $files[$i];
  # iterate over reference categories
  foreach my $key (@rlist)
  {
    # check that category is present
    if(!defined($f2data{$key}))
    {
      printf STDERR "Query file missing category %s\n", $key;
      next;
    }
    
    if(index($key, "=") > -1)
    {
      # multi-field category
      my $category = substr($key, 0, length($key) - 2);
      foreach my $keyItem (sort(keys(%{$f1data{$key}})))
      {
        # check that item is present
        if(!defined($f2data{$key}{$keyItem}))
        {
          printf STDERR "Enumerated item %s missing in category %s\n", $keyItem, $category;
          next;
        }
        
        # iterate over fields
        my @fieldnames = keys(%{$f1data{$key}{$keyItem}});
        for(my $i = 0; $i <= $#fieldnames; $i++)
        {
          # check that field is present for this item
          if(!defined($f2data{$key}{$keyItem}{$fieldnames[$i]}))
          {
            printf STDERR "Field %s missing from enumerated item %s missing in category %s\n", $fieldnames[$i], $keyItem, $category;
            next;
          }
          
          # compare values
          next if($f1data{$key}{$keyItem}{$fieldnames[$i]} ==
                  $f2data{$key}{$keyItem}{$fieldnames[$i]});
          
          my $delta = $f2data{$key}{$keyItem}{$fieldnames[$i]} -
            $f1data{$key}{$keyItem}{$fieldnames[$i]};
          my $pctDelta = 100;
          
          if($f1data{$key}{$keyItem}{$fieldnames[$i]} != 0)
          {
            $pctDelta = 100 * $delta / $f1data{$key}{$keyItem}{$fieldnames[$i]};
          }
          
          # print category, keyItem, fieldname, f1val, f2val, delta, pctDelta
          if(!$printedHeader)
          {
            printf("%s\n", $header);
            printf("--------------------------------------------------------\n");
            $printedHeader = 1;
          }
          printf("%s %s-%s\t%s\t%s\t%.2f\t%.2f\n",
                 $category, $keyItem, $fieldnames[$i],
                 $f1data{$key}{$keyItem}{$fieldnames[$i]},                
                 $f2data{$key}{$keyItem}{$fieldnames[$i]},
                 $delta, $pctDelta);
        }
      }
    }
    else
    {
      foreach my $keyVar (sort(keys(%{$f1data{$key}})))
      {
        if(!defined($f2data{$key}{$keyVar}))
        {
          printf STDERR "Query file missing statistic %s in category %s\n", $keyVar, $key;
          next;
        }
        
        # compare values
        next if($f1data{$key}{$keyVar} == $f2data{$key}{$keyVar});
        
        my $delta = $f2data{$key}{$keyVar} - $f1data{$key}{$keyVar};
        my $pctDelta = 100;
        
        if($f1data{$key}{$keyVar} != 0)
        {
          $pctDelta = 100 * $delta / $f1data{$key}{$keyVar};
        }
        
        # print category, keyVar, f1val, f2val, delta, pctDelta
        if(!$printedHeader)
        {
          printf("%s\n", $header);
          printf("--------------------------------------------------------\n");
          $printedHeader = 1;
        }
        printf("%s %s\t%s\t%s\t%.2f\t%.2f\n",
               $key, $keyVar,
               $f1data{$key}{$keyVar},                
               $f2data{$key}{$keyVar},
               $delta, $pctDelta);
      }
    }
  }
  printf "\n\n";
}

if($verboseLevel)
{
  print "Done ";
  system("date");
}


sub PrintQCFile(\%)
{
  my $dataRef = @_[0];
  my %data = %$dataRef;

  foreach my $key (keys(%data))
  {
    if(index($key, "=") > -1)
    {
      # multi-field category
      printf "[%s]\n", substr($key,0,length($key)-2);
      # iterate over item numbers/total in category
      foreach my $keyItem (keys(%{$data{$key}}))
      {
        printf("%s=", $keyItem);
        my @fieldnames = keys(%{$data{$key}{$keyItem}});
        printf "%s", $data{$key}{$keyItem}{$fieldnames[0]};
        for(my $i = 1; $i <= $#fieldnames; $i++)
        {
          printf ",%s", $data{$key}{$keyItem}{$fieldnames[$i]};
        }
        printf "\n";
      }
    }
    else
    {
      # simple category
      printf "[%s]\n", $key;
      # iterate over values in category
      foreach my $keyVar (keys(%{$data{$key}}))
      {
        printf "%s=%s\n", $keyVar, $data{$key}{$keyVar};
      }
    }
    printf "\n";
  }
}

sub ReadQCFile($)
{
  my $fname = shift;

  my $i;
  my $category;
  my @fieldnames;
  my $item;
  my %data;
  my $firstTime = ($#rlist == -1);
  
  my $fh = new FileHandle $fname, "r"
    or die "Failed to open $fname for reading";
  while(<$fh>)
  {
    s/[\n\r\cZ]//g;
    
    next if(length($_) == 0);

    if(substr($_,0,1) eq "[")
    {
      # new category
      m/^\[(.*)\]$/;

      my $eqPos = index($1,"=");
      if($eqPos == -1)
      {
        # category has no field names
        $category = $1;
        $#fieldnames = -1;
      }
      else
      {
        # category has comma-delimited list of field names
        # keep the = sign to detect type of category later
        $category = substr($1,0,$eqPos+1);

        @fieldnames = split ",", substr($1,$eqPos+1);
      }
      push @rlist, $category if($firstTime);
    }
    else
    {
      my @keyVal = split "=";
      if($#fieldnames > -1)
      {
        # line has comma-delimited field values
        my @fieldvals = split ",", $keyVal[1];
        if($#fieldvals != $#fieldnames)
        {
          printf STDERR "ERROR: number of field names != number of values!\n";
          exit -1;
        }
        for($i = 0; $i <= $#fieldnames; $i++)
        {
          $data{$category}{$keyVal[0]}{$fieldnames[$i]} = $fieldvals[$i];
        }
      }
      else
      {
        # no fields in this category
        $data{$category}{$keyVal[0]} = $keyVal[1];
      }
    }
  }
  close($fh);
  
  return %data;
}
