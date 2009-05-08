use strict;

sub findOvermerryFailures ($$) {
    my $outDir   = shift @_;
    my $ovmJobs  = shift @_;
    my $failures = 0;

    for (my $i=1; $i<=$ovmJobs; $i++) {
        my $out = substr("0000" . $i, -4);
        if (! -e "$wrk/$outDir/seeds/$out.ovm.gz") {
            $failures++;
        }
    }

    return $failures;
}


sub findOlapFromSeedsFailures ($$) {
    my $outDir   = shift @_;
    my $olpJobs  = shift @_;
    my $failures = 0;

    for (my $i=1; $i<=$olpJobs; $i++) {
        my $out = substr("0000" . $i, -4);
        if (! -e "$wrk/$outDir/olaps/$out.ovb.gz") {
            $failures++;
        }
    }

    return $failures;
}


sub merOverlapper($) {
    my $isTrim = shift @_;

    return if (-d "$wrk/$asm.ovlStore");
    return if (-d "$wrk/$asm.obtStore") && ($isTrim eq "trim");

    caFailure("mer overlapper detected no fragments", undef) if ($numFrags == 0);
    caFailure("mer overlapper doesn't know if trimming or assembling", undef) if (!defined($isTrim));

    my ($outDir, $ovlOpt, $merSize, $merComp, $merType, $merylNeeded);

    #  Set directories and parameters for either 'trimming' or 'real'
    #  overlaps.

    if ($isTrim eq "trim") {
        $outDir      = "0-overlaptrim-overlap";
        $ovlOpt      = "-G";
        $merSize     = getGlobal("obtMerSize");
        $merComp     = getGlobal("merCompression");
        $merType     = "obt";
        $merylNeeded = (getGlobal("obtMerThreshold") =~ m/auto/) ? 1 : 0;
    } else {
        $outDir      = "1-overlapper";
        $ovlOpt      = "";
        $merSize     = getGlobal("ovlMerSize");
        $merComp     = getGlobal("merCompression");
        $merType     = "ovl";
        $merylNeeded = (getGlobal("ovlMerThreshold") =~ m/auto/) ? 1 : 0;
    }

    system("mkdir $wrk/$outDir")       if (! -d "$wrk/$outDir");
    system("mkdir $wrk/$outDir/seeds") if (! -d "$wrk/$outDir/seeds");
    system("mkdir $wrk/$outDir/olaps") if (! -d "$wrk/$outDir/olaps");

    #  Make the directory (to hold the corrections output) and claim
    #  that fragment correction is all done.  after this, the rest of
    #  the fragment/overlap correction pipeline Just Works.
    #
    system("mkdir $wrk/3-overlapcorrection") if ((! -d "$wrk/3-overlapcorrection") && ($isTrim ne "trim"));

    my $ovmBatchSize = getGlobal("merOverlapperSeedBatchSize");
    my $ovmJobs      = int(($numFrags - 1) / $ovmBatchSize) + 1;

    my $olpBatchSize = getGlobal("merOverlapperExtendBatchSize");
    my $olpJobs      = int(($numFrags - 1) / $olpBatchSize) + 1;

    #  Need mer counts, unless there is only one partition.
    meryl() if (($ovmJobs > 1) || ($merylNeeded));

    #  Create overmerry and olap-from-seeds jobs
    #
    if (! -e "$wrk/$outDir/overmerry.sh") {
        open(F, "> $wrk/$outDir/overmerry.sh") or caFailure("can't open '$wrk/$outDir/overmerry.sh'", undef);
        print F "#!/bin/sh\n";
        print F "\n";
        print F "jobid=\$SGE_TASK_ID\n";
        print F "if [ x\$jobid = x -o x\$jobid = xundefined ]; then\n";
        print F "  jobid=\$1\n";
        print F "fi\n";
        print F "if [ x\$jobid = x ]; then\n";
        print F "  echo Error: I need SGE_TASK_ID set, or a job index on the command line.\n";
        print F "  exit 1\n";
        print F "fi\n";
        print F "\n";
        print F "jobid=`printf %04d \$jobid`\n";
        print F "minid=`expr \$jobid \\* $ovmBatchSize - $ovmBatchSize + 1`\n";
        print F "maxid=`expr \$jobid \\* $ovmBatchSize`\n";
        print F "runid=\$\$\n";
        print F "\n";
        print F "if [ \$maxid -gt $numFrags ] ; then\n";
        print F "  maxid=$numFrags\n";
        print F "fi\n";
        print F "if [ \$minid -gt \$maxid ] ; then\n";
        print F "  echo Job partitioning error -- minid=\$minid maxid=\$maxid.\n";
        print F "  exit\n";
        print F "fi\n";
        print F "\n";
        print F "AS_OVL_ERROR_RATE=", getGlobal("ovlErrorRate"), "\n";
        print F "AS_CNS_ERROR_RATE=", getGlobal("cnsErrorRate"), "\n";
        print F "AS_CGW_ERROR_RATE=", getGlobal("cgwErrorRate"), "\n";
        print F "export AS_OVL_ERROR_RATE AS_CNS_ERROR_RATE AS_CGW_ERROR_RATE\n";
        print F "\n";
        print F "if [ ! -d $wrk/$outDir/seeds ]; then\n";
        print F "  mkdir $wrk/$outDir/seeds\n";
        print F "fi\n";
        print F "\n";
        print F "if [ -e $wrk/$outDir/seeds/\$jobid.ovm.gz ]; then\n";
        print F "  echo Job previously completed successfully.\n";
        print F "  exit\n";
        print F "fi\n";

        print F getBinDirectoryShellCode();

        print F "\$bin/overmerry \\\n";
        print F " -g  $wrk/$asm.gkpStore \\\n";
        if ($ovmJobs > 1) {
            print F " -mc $wrk/0-mercounts/$asm-C-ms$merSize-cm$merComp \\\n";
            print F " -tb \$minid -te \$maxid \\\n";
            print F " -qb \$minid \\\n";
        }
        print F " -m $merSize \\\n";
        print F " -c $merComp \\\n";
        print F " -T ", getGlobal("obtMerThreshold"), " \\\n" if ($isTrim eq "trim");
        print F " -T ", getGlobal("ovlMerThreshold"), " \\\n" if ($isTrim ne "trim");
        print F " -t " . getGlobal("merOverlapperThreads") . "\\\n";
        print F " -o $wrk/$outDir/seeds/\$jobid.ovm.WORKING.gz \\\n";
        print F "&& \\\n";
        print F "mv $wrk/$outDir/seeds/\$jobid.ovm.WORKING.gz $wrk/$outDir/seeds/\$jobid.ovm.gz\n";
        close(F);

        system("chmod +x $wrk/$outDir/overmerry.sh");
    }

    if (! -e "$wrk/$outDir/olap-from-seeds.sh") {
        open(F, "> $wrk/$outDir/olap-from-seeds.sh") or caFailure("can't open '$wrk/$outDir/olap-from-seeds.sh'", undef);
        print F "#!/bin/sh\n";
        print F "\n";
        print F "jobid=\$SGE_TASK_ID\n";
        print F "if [ x\$jobid = x -o x\$jobid = xundefined ]; then\n";
        print F "  jobid=\$1\n";
        print F "fi\n";
        print F "if [ x\$jobid = x ]; then\n";
        print F "  echo Error: I need SGE_TASK_ID set, or a job index on the command line.\n";
        print F "  exit 1\n";
        print F "fi\n";
        print F "\n";
        print F "jobid=`printf %04d \$jobid`\n";
        print F "minid=`expr \$jobid \\* $olpBatchSize - $olpBatchSize + 1`\n";
        print F "maxid=`expr \$jobid \\* $olpBatchSize`\n";
        print F "runid=\$\$\n";
        print F "\n";
        print F "if [ \$maxid -gt $numFrags ] ; then\n";
        print F "  maxid=$numFrags\n";
        print F "fi\n";
        print F "if [ \$minid -gt \$maxid ] ; then\n";
        print F "  echo Job partitioning error -- minid=\$minid maxid=\$maxid.\n";
        print F "  exit\n";
        print F "fi\n";
        print F "\n";
        print F "AS_OVL_ERROR_RATE=", getGlobal("ovlErrorRate"), "\n";
        print F "AS_CNS_ERROR_RATE=", getGlobal("cnsErrorRate"), "\n";
        print F "AS_CGW_ERROR_RATE=", getGlobal("cgwErrorRate"), "\n";
        print F "export AS_OVL_ERROR_RATE AS_CNS_ERROR_RATE AS_CGW_ERROR_RATE\n";
        print F "\n";
        print F "if [ ! -d $wrk/$outDir/olaps ]; then\n";
        print F "  mkdir $wrk/$outDir/olaps\n";
        print F "fi\n";
        print F "\n";
        print F "if [ -e $wrk/$outDir/olaps/\$jobid.ovb.gz ]; then\n";
        print F "  echo Job previously completed successfully.\n";
        print F "  exit\n";
        print F "fi\n";

        print F getBinDirectoryShellCode();

        print F "\$bin/olap-from-seeds \\\n";
        print F " -a -b \\\n";
        print F " -t " . getGlobal("merOverlapperThreads") . "\\\n";
        print F " -S $wrk/$outDir/$asm.merStore \\\n";

        if ($isTrim eq "trim") {
            print F " -G \\\n";  #  Trim only
            print F " -o $wrk/$outDir/olaps/\$jobid.ovb.WORKING.gz \\\n";
            print F " $wrk/$asm.gkpStore \\\n";
            print F " \$minid \$maxid \\\n";
            print F " > $wrk/$outDir/olaps/$asm.\$jobid.ovb.err 2>&1 \\\n";
            print F "&& \\\n";
            print F "mv $wrk/$outDir/olaps/\$jobid.ovb.WORKING.gz $wrk/$outDir/olaps/\$jobid.ovb.gz\n";
        } else {
            print F " -w \\\n" if (getGlobal("merOverlapperCorrelatedDiffs"));
            print F " -c $wrk/3-overlapcorrection/\$jobid.frgcorr.WORKING \\\n";
            print F " -o $wrk/$outDir/olaps/\$jobid.ovb.WORKING.gz \\\n";
            print F " $wrk/$asm.gkpStore \\\n";
            print F " \$minid \$maxid \\\n";
            print F " > $wrk/$outDir/olaps/$asm.\$jobid.ovb.err 2>&1 \\\n";
            print F "&& \\\n";
            print F "mv $wrk/$outDir/olaps/\$jobid.ovb.WORKING.gz $wrk/$outDir/olaps/\$jobid.ovb.gz \\\n";
            print F "&& \\\n";
            print F "mv $wrk/3-overlapcorrection/\$jobid.frgcorr.WORKING $wrk/3-overlapcorrection/\$jobid.frgcorr \\\n";
            print F "\n";
            print F "rm -f $wrk/3-overlapcorrection/\$jobid.frgcorr.WORKING\n";
        }

        print F "\n";
        print F "rm -f $wrk/$outDir/olaps/\$jobid.ovb.WORKING\n";
        print F "rm -f $wrk/$outDir/olaps/\$jobid.ovb.WORKING.gz\n";

        close(F);

        system("chmod +x $wrk/$outDir/olap-from-seeds.sh");
    }


    #  To prevent infinite loops -- stop now if the overmerry script
    #  exists.  This will unfortunately make restarting from transient
    #  failures non-trivial.
    #
    #  FAILUREHELPME
    #
    my $ovmFailures = findOvermerryFailures($outDir, $ovmJobs);
    if (($ovmFailures != 0) && ($ovmFailures < $ovmJobs)) {
        caFailure("mer overlapper seed finding failed", undef);
    }

    #  Submit to the grid (or tell the user to do it), or just run
    #  things here
    #
    if (findOvermerryFailures($outDir, $ovmJobs) > 0) {
        if (getGlobal("useGrid") && getGlobal("ovlOnGrid")) {
            my $sge        = getGlobal("sge");
            my $sgeOverlap = getGlobal("sgeMerOverlapSeed");

            my $SGE;
            $SGE  = "qsub $sge $sgeOverlap -N mer_$asm \\\n";
            $SGE .= "  -t 1-$ovmJobs \\\n";
            $SGE .= "  -j y -o $wrk/$outDir/seeds/\\\$TASK_ID.out \\\n";
            $SGE .= "  $wrk/$outDir/overmerry.sh\n";

            submitBatchJobs($SGE, "mer_$asm");
            exit(0);
        } else {
            for (my $i=1; $i<=$ovmJobs; $i++) {
                my $out = substr("0000" . $i, -4);
                &scheduler::schedulerSubmit("sh $wrk/$outDir/overmerry.sh $i > $wrk/$outDir/seeds/$out.out 2>&1 && rm -f $wrk/$outDir/seeds/$out.out");
            }

            &scheduler::schedulerSetNumberOfProcesses(getGlobal("merOverlapperSeedConcurrency"));
            &scheduler::schedulerFinish();
        }
    }

    #  Make sure everything finished ok.
    #
    #  FAILUREHELPME
    #
    {
        my $f = findOvermerryFailures($outDir, $ovmJobs);
        caFailure("there were $f overmerry failures", undef) if ($f > 0);
    }

    if (runCommand($wrk, "find $wrk/$outDir/seeds -name \\*ovm.gz -print > $wrk/$outDir/$asm.merStore.list")) {
        caFailure("failed to generate a list of all the overlap files", undef);
    }

    if (! -e "$wrk/$outDir/$asm.merStore") {
        my $bin = getBinDirectory();
        my $cmd;
        $cmd  = "$bin/overlapStore";
        $cmd .= " -c $wrk/$outDir/$asm.merStore.WORKING";
        $cmd .= " -g $wrk/$asm.gkpStore";
        $cmd .= " -M " . getGlobal("ovlStoreMemory");
        $cmd .= " -L $wrk/$outDir/$asm.merStore.list";
        $cmd .= " > $wrk/$outDir/$asm.merStore.err 2>&1";

        if (runCommand($wrk, $cmd)) {
            caFailure("overlap store building failed", "$wrk/$outDir/$asm.merStore.err");
        }

        rename "$wrk/$outDir/$asm.merStore.WORKING", "$wrk/$outDir/$asm.merStore";

        rmrf("$outDir/$asm.merStore.list");
        rmrf("$outDir/$asm.merStore.err");
    }


    #  To prevent infinite loops -- stop now if the overmerry script
    #  exists.  This will unfortunately make restarting from transient
    #  failures non-trivial.
    #
    #  FAILUREHELPME
    #
    my $olpFailures = findOlapFromSeedsFailures($outDir, $olpJobs);
    if (($olpFailures != 0) && ($olpFailures < $olpJobs)) {
        caFailure("mer overlapper extension failed", undef);
    }

    #  Submit to the grid (or tell the user to do it), or just run
    #  things here
    #
    if (findOlapFromSeedsFailures($outDir, $olpJobs) > 0) {
        if (getGlobal("useGrid") && getGlobal("ovlOnGrid")) {
            my $sge        = getGlobal("sge");
            my $sgeOverlap = getGlobal("sgeMerOverlapExtend");

            my $SGE;
            $SGE  = "qsub $sge $sgeOverlap -N olp_$asm \\\n";
            $SGE .= "  -t 1-$olpJobs \\\n";
            $SGE .= "  -j y -o $wrk/$outDir/olaps/\\\$TASK_ID.out \\\n";
            $SGE .= "  $wrk/$outDir/olap-from-seeds.sh\n";

            submitBatchJobs($SGE, "olp_$asm");
            exit(0);
        } else {
            for (my $i=1; $i<=$olpJobs; $i++) {
                my $out = substr("0000" . $i, -4);
                &scheduler::schedulerSubmit("sh $wrk/$outDir/olap-from-seeds.sh $i > $wrk/$outDir/olaps/$out.out 2>&1");
            }

            &scheduler::schedulerSetNumberOfProcesses(getGlobal("merOverlapperExtendConcurrency"));
            &scheduler::schedulerFinish();
        }
    }

    #  Make sure everything finished ok.
    #
    #  FAILUREHELPME
    #
    {
        my $f = findOlapFromSeedsFailures($outDir, $olpJobs);
        caFailure("there were $f olap-from-seeds failures", undef) if ($f > 0);
    }
}
