#charset "us-ascii"
//
// sample.t
// Version 1.0
// Copyright 2022 Diegesis & Mimesis
//
// This is a very simple demonstration "game" for the dynamicVocab library.
//
// It can be compiled via the included makefile with
//
//	# t3make -f makefile.t3m
//
// ...or the equivalent, depending on what TADS development environment
// you're using.
//
// This "game" is distributed under the MIT License, see LICENSE.txt
// for details.
//
#include <adv3.h>
#include <en_us.h>

#include "dynamicVocab.h"

versionInfo: GameID;
gameMain: GameMainDef
	initialPlayerChar = me
	alienToggle = nil
	weirdToggle = nil
;

startRoom: Room 'Void' "This is a featureless void.";
+me: Person;
+pebble: Thing, DynamicVocab '(small) (round) pebble' 'pebble'
	"A small, round pebble. "
;
++alien: VocabCfg '(alien) artifact';
++weird: VocabCfg '(weird) artifact';

DefineSystemAction(Alien)
	execSystemAction() {
		if(gameMain.alienToggle == nil) {
			pebble.activateVocab(alien);
			defaultReport('Adding <q>alien</q> vocab. ');
		} else {
			pebble.deactivateVocab(alien);
			defaultReport('Removing <q>alien</q> vocab. ');
		}
		gameMain.alienToggle = !gameMain.alienToggle;
		pebble.syncVocab();
	}
;
VerbRule(Alien) 'alien' : AlienAction verbPhrase = 'alien/alienating';

DefineSystemAction(Weird)
	execSystemAction() {
		if(gameMain.weirdToggle == nil) {
			pebble.activateVocab(weird);
			defaultReport('Adding <q>weird</q> vocab. ');
		} else {
			pebble.deactivateVocab(weird);
			defaultReport('Removing <q>weird</q> vocab. ');
		}
		gameMain.weirdToggle = !gameMain.weirdToggle;
		pebble.syncVocab();
	}
;
VerbRule(Weird) 'weird' : WeirdAction verbPhrase = 'weird/weirding';
