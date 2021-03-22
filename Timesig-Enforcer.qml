import QtQuick 2.0
import MuseScore 3.0

MuseScore {
      menuPath: "Plugins.Time Signatures.Enforce"
      description: "Enforces measure actual duration to match the time signature for it.\nEither select a range of measures on which to run or runs on the entire score."
      version: "1.0.0"
      requiresScore: true
      onRun: {
            // Get applicable range
            var sel = curScore ? curScore.selection : null;
            var rangeToProcess = {
                  startSeg: (sel && sel.isRange)? sel.startSegment : curScore.firstMeasure.firstSegment,
                  endSeg: (sel && sel.isRange)? sel.endSegment : curScore.lastSegment
            };
            console.log("rangeToProcess: ", rangeToProcess.startSeg.tick, rangeToProcess.endSeg.tick);
            // Find first measure in range
            var m = rangeToProcess.startSeg;
            while (m && (m.type != Element.MEASURE)) {
                  console.log("moving up the chain", m);
                  m = m.parent;
            }
            console.log("Found m = ", m, (m? m.firstSegment.tick : "NaN"));
            
            // Loop over all measures in range
            while (m && (m.firstSegment.tick < rangeToProcess.endSeg.tick)) {
                  //console.log("Processing: ", m.firstSegment.tick);
                  if (m.timesigActual.ticks < m.timesigNominal.ticks) {
                        var durationTicksToAdd = m.timesigNominal.ticks - m.timesigActual.ticks;
                        console.log("\nEXPAND", m.firstSegment.tick, "from", m.timesigActual.str, "to", m.timesigNominal.str, "by adding", durationTicksToAdd, "ticks.");
                        // Let's insert time at the end of the measure
                        var lastCR = m.lastSegment;
                        while (lastCR.segmentType != Segment.ChordRest) {
                              lastCR = lastCR.prevInMeasure;
                        }
                        var insertBeforeElement = null, i = curScore.ntracks;
                        do {
                              --i;
                              insertBeforeElement = lastCR.elementAt(i);
                        } while ( (i > 0)
                               && (  (insertBeforeElement == null)
                                  || ((insertBeforeElement.type != Element.REST) && (insertBeforeElement.type != Element.CHORD))
                                  )
                               );
                        var durationOfAddedElement = insertBeforeElement.duration.ticks; // New element will match duration with existing element
                        if (insertBeforeElement.type == Element.CHORD) {
                              // Can't select a chord, we need to select a note within it instead
                              insertBeforeElement = insertBeforeElement.notes[0];
                        }
                        curScore.startCmd();
                        if (curScore.selection.select(insertBeforeElement)) {
                              // We can only insert time before the current last element, so let's do that
                              // And we can only swap the inserted time with the original last element if they have matching durations
                              // There is no way to insert rests, so let's add notes and then delete them
                              cmd("insert-a");
                              cmd("move-right");
                              durationTicksToAdd -= durationOfAddedElement;
                              while (durationTicksToAdd > 0) {
                                    cmd("insert-a");
                                    durationTicksToAdd -= durationOfAddedElement;
                                    cmd("prev-chord"); // Maintain Selection on left-most of the added notes
                              }
                              // Turn those notes into rests
                              cmd("escape"); // Out of note-entry mode, which was triggered by the insert-a action
                              // select-next-measure is bugged when used on the last segment of a measure
                              // So let's try to verify whether we're in this situation
                              var leftMostElementToClear = curScore.selection.elements[0];
                              while (leftMostElementToClear && (leftMostElementToClear.type != Element.SEGMENT)) {
                                    leftMostElementToClear = leftMostElementToClear.parent;
                              }
                              // Try to find the next chordrest within the measure
                              var nextCR = (leftMostElementToClear)? leftMostElementToClear.nextInMeasure : null;
                              while (nextCR && (nextCR.segmentType != Segment.ChordRest)) {
                                    nextCR = nextCR.nextInMeasure;
                              }
                              cmd("select-next-measure");
                              if (nextCR == null) {
                                    // We started from the last segment in the measure
                                    // The bug will make us select one more chordrest segment into the next measure
                                    cmd("select-prev-chord");
                              }
                              cmd("delete");
                        }
                        else { console.log("Failed to select element to insert before"); }
                        curScore.endCmd();
                        console.log("rangeToProcess.endSeg.tick", rangeToProcess.endSeg.tick);
                  }
                  
                  if (m.timesigActual.ticks > m.timesigNominal.ticks) {
                        console.log("\nSHRINK", m.firstSegment.tick, "from", m.timesigActual.str, "to", m.timesigNominal.str, "by removing", (m.timesigActual.ticks - m.timesigNominal.ticks), "ticks.");
                        // Hop segments to find the ChordRest to shorten/remove
                        var measureEndTick = m.firstSegment.tick + m.timesigNominal.ticks;
                        var chordRestToClip = m.firstSegment;
                        while (chordRestToClip && (chordRestToClip.segmentType != Segment.ChordRest)) {
                              chordRestToClip = chordRestToClip.nextInMeasure;
                        }
                        var nextCR = chordRestToClip;
                        while (nextCR && (nextCR.tick < measureEndTick)) {
                              chordRestToClip = nextCR;
                              do {
                                    nextCR = nextCR.nextInMeasure;
                              } while (nextCR && (nextCR.segmentType != Segment.ChordRest));
                        }
                        //console.log("Clip from segment", chordRestToClip.tick, " | clip to new length", measureEndTick - chordRestToClip.tick);
                        var newSegmentLength = measureEndTick - chordRestToClip.tick;
                        var chordRestsInSegment = [];
                        for (var i = curScore.ntracks; i-- > 0; ) {
                              var el = chordRestToClip.elementAt(i);
                              if (el && ((el.type == Element.REST) || (el.type == Element.CHORD))) {
                                    chordRestsInSegment.push(el);
                              }
                        }
                        //console.log(chordRestsInSegment, chordRestsInSegment.length);
                        // Try to clip from the closest matching duration
                        chordRestToClip = chordRestsInSegment[0];
                        for (i = chordRestsInSegment.length; i-- > 1; ) {
                              if (chordRestsInSegment[i].duration.ticks < chordRestToClip.duration.ticks) {
                                    chordRestToClip = chordRestsInSegment[i];
                              }
                        }
                        console.log("Clipping from segment chordRest with duration:", chordRestToClip.duration.str);//, chordRestToClip.globalDuration.str, chordRestToClip.actualDuration.str);
                        curScore.startCmd();
                        // Is clipping required to create a segment boundary?
                        var currentSegmentLength = chordRestToClip.duration.ticks;
                        var isChord = (chordRestToClip.type == Element.CHORD);
                        if (isChord) {
                              // Can't select a chord, so will need to select a note in it instead
                              chordRestToClip = chordRestToClip.notes[0];
                        }
                        
                        //console.log(newSegmentLength, currentSegmentLength);
                        if (curScore.selection.select(chordRestToClip)) {
                              if (newSegmentLength < currentSegmentLength) {
                                    console.log("adjusting duration");
                                    var num = newSegmentLength / division; // in quarter notes
                                    var den = 4;
                                    if (num < 1) {
                                          den /= num;
                                          num = 1;
                                    }
                                    //else if (num > 1) {
                                    //      den *= num;
                                    //      num = 1;
                                    //}

                                    function reduce(numerator, denominator)
                                    {
                                          var a = numerator;
                                          var b = denominator;
                                          var c;
                                          while (b) {
                                                c = a % b;
                                                a = b;
                                                b = c;
                                          }
                                          return { n: (numerator / a), d: (denominator / a) };
                                    }
                                    
                                    // Try to simplify desired clipped duration
                                    var frac = reduce(num, den);
                                    var wholes = Math.floor(frac.n / frac.d);
                                    frac.n -= wholes * frac.d;
                                    // We could have up to a quadruple dotted base note
                                    var baseDuration = Math.pow(2, Math.floor(Math.log(frac.n) / Math.LN2));
                                    var remainder = frac.n - baseDuration;
                                    var dotDuration = baseDuration / 2;
                                    var dots = 0;
                                    while ((remainder >= dotDuration) && (dots < 4)) {
                                          ++dots;
                                          remainder -= dotDuration;
                                          dotDuration /= 2;
                                    }
                                    if (wholes && (dots < 4) && (baseDuration == (frac.d/2))) {
                                          // incorporate one whole note as starting duration
                                          --wholes;
                                          frac.n += frac.d;
                                          baseDuration = frac.d;
                                          ++dots;
                                    }

                                    console.log(frac.n+"/"+frac.d, "wholes:", wholes, "baseDuration:", baseDuration, "dots:", dots, "remainder:", remainder);
                                    var baseFrac = reduce(baseDuration, frac.d);
                                    var remainingFrac = reduce(remainder, frac.d);

                                    console.log("wholes", wholes, "baseFrac:", baseFrac.n+"/"+baseFrac.d, "dots:", dots, "remainingFrac:", remainingFrac.n+"/"+remainingFrac.d);
                                    var firstDurationChange = true;
                                    while (wholes) {
                                          cmd("pad-note-1");
                                          if (firstDurationChange) {
                                                cmd("note-input-steptime");
                                                firstDurationChange = false;
                                          }
                                          else {
                                                cmd((isChord) ? "tie" : "pad-rest");
                                          }
                                          --wholes;
                                    }
                                    if (baseFrac.n == 1) {
                                          cmd("pad-note-" + baseFrac.d);
                                          if (firstDurationChange) {
                                                cmd("note-input-steptime");
                                                firstDurationChange = false;
                                          }
                                          else {
                                                cmd((isChord) ? "tie" : "pad-rest");
                                          }                                          
                                    }
                                    if (dots) {
                                          var dotcmd = "pad-dot";
                                          if (dots == 2) {
                                                dotcmd += "dot";
                                          }
                                          else if (dots > 2) {
                                                dotcmd += "" + dots;
                                          }
                                          cmd(dotcmd);
                                    }
                                    if (remainingFrac.n == 1) {
                                          cmd("pad-note-" + remainingFrac.d);
                                          cmd((isChord) ? "tie" : "pad-rest");
                                    }
                                    
                                    // We have shortened our segment to the required length
                                    // All that is left is to remove the remainder, which is done further down
                              }
                              // else exact match duration, start removing at next segment
                              cmd("next-chord");
                              cmd("select-next-measure");
                              cmd("time-delete");
                        }
                        else { console.log("failed to select element to clip"); }
                                                            
                        //curScore.startCmd();
                        //m.timesigActual = m.timesigNominal;
                        curScore.endCmd();
                        console.log("rangeToProcess.endSeg.tick", rangeToProcess.endSeg.tick);
                  }
                  m = m.nextMeasure;
            }
            
      }
}
