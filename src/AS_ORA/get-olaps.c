
/**************************************************************************
 * This file is part of Celera Assembler, a software program that 
 * assembles whole-genome shotgun reads into contigs and scaffolds.
 * Copyright (C) 1999-2004, Applera Corporation. All rights reserved.
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received (LICENSE.txt) a copy of the GNU General Public 
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *************************************************************************/
/**********************************************************************
$Source: /work/NIGHTLY/wgs-assembler-cvs/src/AS_ORA/Attic/get-olaps.c,v $
$Revision: 1.1.1.1 $
**********************************************************************/

/**********************************************************************
Module: get-olaps

Description: Reads the message file produced by the overlapper and
             extracts and outputs the overlap messages in a condensed
             format suitable for sorting.

             Adapted from Ian Dew's overlap regressor analyzer.

**********************************************************************/


/*********************************************************************/
// headers
// standard headers
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <unistd.h>

// project headers
#include "AS_global.h"
#include "AS_MSG_pmesg.h"
#include "AS_PER_ReadStruct.h"
#include "AS_PER_fragStore.h"
#include "AS_PER_distStore.h"
#include "AS_ORA_fragments.h"
#include "AS_ORA_overlaps.h"
#include "AS_ORA_statistics.h"
#include "AS_ORA_inlines.h"
/*********************************************************************/


/*********************************************************************/
// defines
#ifndef MAX_SEQUENCE_LENGTH
#define MAX_SEQUENCE_LENGTH 2048
#endif

#ifndef MAX_SOURCE_LENGTH
#define MAX_SOURCE_LENGTH 512
#endif
/*********************************************************************/



/*********************************************************************/
// structures
/*********************************************************************/


/*********************************************************************/
// function prototype

int GetOverlaps( char * input_filename,
                 char * output_filename);

/*********************************************************************/


/*********************************************************************/
/* Function:
     main()
   Description:
     top-level function for get-olaps
   Return Value:
     0 if ok
   Parameters:
     <filename>.ovl    ASCII overlap message filename
                       (NOTE: This will change to a binary file when
                              the I/O routines (and files) are ready)
*/

int main( int argc, char ** argv )
{
  char              * input_ovl_filename = NULL;
  char              * output_ovl_filename = NULL;

  // parse the command line parameters
  // use getopt(): see "man 3 getopt"
  {
    int ch, errflg = 0;
    optarg = NULL;
    while( !errflg && ((ch = getopt( argc, argv, "s:i:o:l:" )) != EOF) )
    {
      switch( ch )
      {
        case 'i':
          input_ovl_filename = optarg;
          break;
        case '?':
          fprintf( stderr, "Unrecognized option -%c\n", optopt );
        default:
          errflg++;
          break;
      }
    }

    // need fragstore_name & min_overlap and one or both of
    // input and output ovl filenames
    if( errflg != 0
          ||  input_ovl_filename == NULL)
    {
      fprintf( stderr, "Usage: %s\n"
               " -i input-overlap-filename\n",
               argv[0] );
    return 1;
    }
  }

    if( GetOverlaps(input_ovl_filename,
                    output_ovl_filename))
    {
      fprintf( stderr, "Failed to copy overlaps.\n" );
      return 1;
    }

  fprintf( stderr, "Done.\n" );
  return 0;
}



/* Function:
     GetOverlaps
   Description:
     Copies overlap messages from input file to output file in
     condensed format
   Return Value:
     0 if ok
   Parameters:
     char * input_ovl_filename: name of overlap message file
     char * output_ovl_filename: name of condensed output file
*/

int GetOverlaps( char * input_ovl_filename,
                 char * output_ovl_filename)
{
  FILE * infile = fopen( input_ovl_filename, "r" );
  GenericMesg * gmesg = NULL;
  OverlapMesg * osp = NULL;
  MesgReader  Read_Msg_Fn;

  
  if( infile == NULL )
  {
    fprintf( stderr,
             "Failed to open overlap messages %s for reading.\n",
             input_ovl_filename );
    return 1;
  }

  Read_Msg_Fn = InputFileType_AS (infile);

  // read the found overlaps in one-at-a-time
  while( Read_Msg_Fn( infile, &gmesg ) != EOF )
  {
    if( gmesg && gmesg->t == MESG_OVL )
    {
      // deal with the generic message as an overlap message
      osp = (OverlapMesg *) gmesg->m;
      
      printf ("%8d %8d %5d %5d  %c %5.2f\n",
              osp -> aifrag, osp -> bifrag, osp -> ahg, osp -> bhg,
              (char) (osp -> orientation), 100.0 * osp -> quality);
    }
  }

  // clean up
  fclose( infile );

  return 0;
}

