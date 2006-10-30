use strict;

#  Check and apply the overlap correction results.

sub applyOverlapCorrection {

    return if (getGlobal("doFragmentCorrection") == 0);

    my $ovlCorrBatchSize    = getGlobal("ovlCorrBatchSize");

    if (! -e "$wrk/3-ovlcorr/update-erates.success") {
        my $failedJobs = 0;

        open(F, "> $wrk/3-ovlcorr/cat-erates.eratelist");

        my $jobs = int($numFrags / ($ovlCorrBatchSize-1)) + 1;
        for (my $i=1; $i<=$jobs; $i++) {
            my $frgBeg = $i * $ovlCorrBatchSize - $ovlCorrBatchSize + 1;
            my $frgEnd = $i * $ovlCorrBatchSize;
            if ($frgEnd > $numFrags) {
                $frgEnd = $numFrags - 1;
            }
            $frgBeg = substr("00000000$frgBeg", -8);
            $frgEnd = substr("00000000$frgEnd", -8);

            if (! -e "$wrk/3-ovlcorr/$asm-$frgBeg-$frgEnd.success") {
                print STDERR "Overlap correction job $i ($wrk/3-ovlcorr/$asm-$frgBeg-$frgEnd) failed.\n";
                $failedJobs++;
            }

            print F "$wrk/3-ovlcorr/$asm-$frgBeg-$frgEnd.erate\n";
        }

        close(F);

        die "$failedJobs failed.  Good luck.\n" if ($failedJobs);

        if (! -e "$wrk/3-ovlcorr/$asm.erates") {
            my $cmd;
            $cmd  = "$bin/cat-erates ";
            $cmd .= "-L $wrk/3-ovlcorr/cat-erates.eratelist ";
            $cmd .= "-o $wrk/3-ovlcorr/$asm.erates ";
            $cmd .= "> $wrk/3-ovlcorr/cat-erates.err 2>&1";
            if (runCommand($cmd)) {
                rename "$wrk/3-ovlcorr/$asm.erates", "$wrk/3-ovlcorr/$asm.erates.FAILED";
                die "Failed to concatenate the overlap erate corrections.\n";
            }
        }

        my $cmd;
        $cmd  = "$bin/update-erates ";
        $cmd .= "$wrk/$asm.ovlStore ";
        $cmd .= "$wrk/3-ovlcorr/$asm.erates";
        $cmd .= "> $wrk/3-ovlcorr/update-erates.err 2>&1";
        if (runCommand($cmd)) {
            die "Failed to apply the overlap corrections.\n";
        }

        touch("$wrk/3-ovlcorr/update-erates.success");
    }
}

1;
