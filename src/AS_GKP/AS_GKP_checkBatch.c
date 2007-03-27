
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

static char CM_ID[] = "$Id: AS_GKP_checkBatch.c,v 1.5 2007-03-27 07:31:59 brianwalenz Exp $";

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "AS_global.h"
#include "AS_GKP_include.h"
#include "AS_PER_gkpStore.h"

int Check_BatchMesg(BatchMesg          *bat_mesg,
                    int                *currentBatchID,
		    time_t              currentTime,
		    int                 verbose){

  GateKeeperBatchRecord  gkpb;
  PHashValue_AS          value;

  clearGateKeeperBatchRecord(&gkpb);

  if (HASH_FAILURE != LookupTypeInPHashTable_AS(gkpStore->phs_private, 
                                                UID_NAMESPACE_AS,
                                                bat_mesg->eaccession, 
                                                AS_IID_BAT, 
                                                FALSE,
                                                stderr,
                                                &value)) {
    printGKPError(stderr, GKPError_BadUniqueBAT);
    fprintf(stderr,"# Check_BatchMessage:  A message with UID " F_UID " exists %s!!! Can't reuse it... bye\n",
	    bat_mesg->eaccession, (value.deleted?"and has been deleted":""));
    return(GATEKEEPER_FAILURE);
  }

  if (bat_mesg->created > currentTime) {
    printGKPError(stderr, GKPError_Time);
    fprintf(stderr,"# Check_BatchMessage: invalid entry time " F_TIME_T " > current time (" F_TIME_T ")\n",
	    bat_mesg->created, currentTime);
    return GATEKEEPER_FAILURE;
  }

  value.type = AS_IID_BAT;
  InsertInPHashTable_AS(&gkpStore->phs_private,
                        UID_NAMESPACE_AS,
                        bat_mesg->eaccession,
                        &value,
                        FALSE,
                        TRUE);

  gkpb.batchUID       = bat_mesg->eaccession;
  gkpb.created        = bat_mesg->created;
  strncpy(gkpb.name,    bat_mesg->name, 255);
  strncpy(gkpb.comment, bat_mesg->comment, 255);
  gkpb.numFragments   = getNumGateKeeperFragments(gkpStore->frg);
  gkpb.numLibraries   = getNumGateKeeperLibrarys(gkpStore->lib);
  gkpb.numLibraries_s = getNumGateKeeperLibrarys(gkpStore->lis);

  if(verbose)
    fprintf(stderr,"* Batch " F_IID "  name:%s  comment:%s\n",
	  value.IID, gkpb.name, gkpb.comment);

  appendGateKeeperBatchStore(gkpStore->bat, &gkpb);

  *currentBatchID = value.IID;

  return GATEKEEPER_SUCCESS;
}


