
/**************************************************************************
 * Copyright (C) 2010, J Craig Venter Institute. All rights reserved.
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

static const char *rcsid = "$Id$";

#include "AS_BAT_bogusUtil.H"

#define MAX_GENOME_SIZE_INPUT 256 * 1024 * 1024


bool
byFragmentID(const genomeAlignment &A, const genomeAlignment &B) {
  return(A.frgIID < B.frgIID);
}

bool
byGenomePosition(const genomeAlignment &A, const genomeAlignment &B) {
  if (A.chnBgn < B.chnBgn)
    //  A clearly before B.
    return(true);

  if (A.chnBgn > B.chnBgn)
    //  A clearly after B.
    return(false);

  if ((A.isRepeat == false) && (B.isRepeat == true))
    //  Start at the same spot, put unique stuff first
    return(true);

  //  Note the second condition above.  If both A and B are repeat=false, byGenomePosition(A,B) and
  //  byGenomePosition(B,A) bth return true, logically impossible.

  return(false);
}




void
addAlignment(vector<genomeAlignment>   &genome,
             int32  frgIID,
             int32  frgBgn, int32  frgEnd, bool  isReverse,
             int32  chnBgn, int32  chnEnd,
             double identity,
             int32  genIID,
             int32  genBgn, int32  genEnd) {
  genomeAlignment  A;

  A.frgIID    = frgIID;
  A.frgBgn    = frgBgn;
  A.frgEnd    = frgEnd;
  A.genIID    = genIID;
  A.genBgn    = genBgn;
  A.genEnd    = genEnd;
  A.chnBgn    = chnBgn;
  A.chnEnd    = chnEnd;
  A.identity  = identity;
  A.isReverse = isReverse;
  A.isSpanned = false;
  A.isRepeat  = true;

  assert(A.frgBgn < A.frgEnd);
  assert(A.genBgn < A.genEnd);

  genome.push_back(A);
}


void
loadNucmer(char                       *nucmerName,
           vector<genomeAlignment>    &genome,
           map<string, int32>         &IIDmap,
           vector<string>             &IIDname,
           vector<referenceSequence>  &refList,
           map<string,uint32>         &refMap,
           double                      minIdentity) {
  FILE  *inFile = 0L;
  char   inLine[1024];

  errno = 0;
  inFile = fopen(nucmerName, "r");
  if (errno)
    fprintf(stderr, "Failed to open '%s' for reading: %s\n", nucmerName, strerror(errno)), exit(1);

  fprintf(stderr, "Loading alignments from '%s'\n", nucmerName);

  //  First FOURE lines are header
  fgets(inLine, 1024, inFile);  //  (file paths)
  fgets(inLine, 1024, inFile);  //  NUCMER
  fgets(inLine, 1024, inFile);  //  (blank)
  fgets(inLine, 1024, inFile);  //  (header)

  //  Scan the header line, counting the number of columns
  uint32  nCols  = 0;
  uint32  wIdent = 0;

  for (uint32 xx=0; inLine[xx]; xx++) {
    if ((wIdent == 0) && (inLine[xx+0] == '[') && (inLine[xx+1] == '%') && (inLine[xx+2] == ' '))
      wIdent = nCols;
    if (inLine[xx] == '[')
      nCols++;
  }

  //  Read the first line.
  fgets(inLine, 1024, inFile);
  chomp(inLine);

  while (!feof(inFile)) {
    for (uint32 xx=0; inLine[xx]; xx++)
      if (inLine[xx] == '|')
        inLine[xx] = ' ';

    splitToWords     W(inLine);
    genomeAlignment  A;
    string           gID = W[nCols - 1];  //  TAGS is the last header column,
    string           fID = W[nCols - 0];  //  but read ID is in column +1 from there.

    if (IIDmap.find(fID) == IIDmap.end()) {
      IIDname.push_back(fID);
      IIDmap[fID] = IIDname.size() - 1;
    }

    //  Unlike snapper, these are already in base-based coords.

    A.frgIID    = IIDmap[fID];
    A.frgBgn    = W(2);
    A.frgEnd    = W(3);
    A.genIID    = refMap[gID];
    A.genBgn    = W(0);
    A.genEnd    = W(1);
    A.chnBgn    = refList[A.genIID].rschnBgn + A.genBgn;
    A.chnEnd    = refList[A.genIID].rschnBgn + A.genEnd;
    A.identity  = atof(W[wIdent]);
    A.isReverse = false;
    A.isSpanned = false;
    A.isRepeat  = true;

    if (A.frgBgn > A.frgEnd) {
      A.frgBgn    = W(3);
      A.frgEnd    = W(2);
      A.isReverse = true;
    }

    if ((A.frgBgn >= A.frgEnd) ||
        (A.genBgn >= A.genEnd)) {
      fprintf(stderr, "ERROR: %s\n", inLine);
      if (A.frgBgn >= A.frgEnd)
        fprintf(stderr, "ERROR: frgBgn,frgEnd = %u,%u\n",
                A.frgBgn, A.frgEnd);
      if (A.genBgn >= A.genEnd)
        fprintf(stderr, "ERROR: genBgn,genEnd = %u,%u\n",
                A.genBgn, A.genEnd);
    }
    assert(A.frgBgn < A.frgEnd);
    assert(A.genBgn < A.genEnd);

    if (A.identity < minIdentity)
      goto nextNucmerLine;

    genome.push_back(A);

  nextNucmerLine:
    fgets(inLine, 1024, inFile);
    chomp(inLine);
  }

  fclose(inFile);
}



void
loadSnapper(char                       *snapperName,
            vector<genomeAlignment>    &genome,
            map<string, int32>         &IIDmap,
            vector<string>             &IIDname,
            vector<referenceSequence>  &refList,
            map<string,uint32>         &refMap,
            double                      minIdentity) {
  FILE  *inFile = 0L;
  char   inLine[1024];

  errno = 0;
  inFile = fopen(snapperName, "r");
  if (errno)
    fprintf(stderr, "Failed to open '%s' for reading: %s\n", snapperName, strerror(errno)), exit(1);

  //  Read the first line
  fgets(inLine, 1024, inFile);
  chomp(inLine);

  while (!feof(inFile)) {
    splitToWords     W(inLine);
    genomeAlignment  A;
    string           fID = W[0];
    string           gID = W[5];

    if ((W[1][0] < '0') || (W[1][0] > '9'))
      //  Skip header lines.
      goto nextSnapperLine;

    if (IIDmap.find(fID) == IIDmap.end()) {
      IIDname.push_back(fID);
      IIDmap[fID] = IIDname.size() - 1;
    }

    //  "+1" -- Convert from space-based coords to base-based coords.

    A.frgIID    = IIDmap[fID];
    A.frgBgn    = W(3) + 1;
    A.frgEnd    = W(4);
    A.genIID    = refMap[gID];
    A.genBgn    = W(6) + 1;
    A.genEnd    = W(7);
    A.chnBgn    = refList[A.genIID].rschnBgn + A.genBgn;
    A.chnEnd    = refList[A.genIID].rschnBgn + A.genEnd;
    A.identity  = atof(W[8]);
    A.isReverse = false;
    A.isSpanned = false;
    A.isRepeat  = true;

    if (A.frgBgn > A.frgEnd) {
      A.frgBgn    = W(4) + 1;
      A.frgEnd    = W(3);
      A.isReverse = true;
    }

    assert(A.frgBgn < A.frgEnd);
    assert(A.genBgn < A.genEnd);

    if (A.identity < minIdentity)
      goto nextSnapperLine;

    genome.push_back(A);

  nextSnapperLine:
    fgets(inLine, 1024, inFile);
    chomp(inLine);
  }

  fclose(inFile);
}



void
loadReferenceSequence(char                       *refName,
                      vector<referenceSequence>  &refList,
                      map<string,uint32>         &refMap) {
  int32     reflen = 0;
  int32     refiid = 0;

  errno = 0;

  FILE     *F      = fopen(refName, "r");

  if (errno)
    fprintf(stderr, "Failed to open reference sequences in '%s': %s\n", refName, strerror(errno)), exit(1);

  char     *refhdr = new char [1024];
  char     *refseq = new char [MAX_GENOME_SIZE_INPUT];

  fgets(refhdr,                  1024, F);   chomp(refhdr);
  fgets(refseq, MAX_GENOME_SIZE_INPUT, F);   chomp(refseq);

  while (!feof(F)) {
    if (refhdr[0] != '>') {
      fprintf(stderr, "ERROR: reference sequences must be one per line.\n");
      exit(1);
    }

    for (uint32 i=0; refhdr[i]; i++) {
      refhdr[i] = refhdr[i+1];  //  remove '>'
      if (isspace(refhdr[i]))   //  stop at first space
        refhdr[i] = 0;
    }

    int32  rl = strlen(refseq);

    refMap[refhdr] = refiid;

    refList.push_back(referenceSequence(reflen, reflen + rl,
                                        rl,
                                        refhdr));

    reflen += rl + 1024;
    refiid++;

    fgets(refhdr,                  1024, F);   chomp(refhdr);
    fgets(refseq, MAX_GENOME_SIZE_INPUT, F);   chomp(refseq);
  }

  fclose(F);
}

