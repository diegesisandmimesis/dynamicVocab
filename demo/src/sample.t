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

startRoom: Room 'Void'
	"This is a featureless void."

	// Ping the pebble's syncVocab() method.  In a real game
	// we'd want to use something a little more elegant, but
	// this is just for testing.
	roomAfterAction() { pebble.syncVocab(); }
;
+me: Person;
+pebble: Thing, DynamicVocab '(small) (round) pebble' 'pebble'
	// The description sets the reveal tag "alien".
	"A small, round pebble.  Which may be an alien
	artifact, apparently.<.reveal alien> "
;
++alien: VocabCfg '(alien) artifact'
	// The "alien" vocabulary is enabled by the "alien" reveal tag.
	isActive = (gRevealed('alien'))
;
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
	}
;
VerbRule(Weird) 'weird' : WeirdAction verbPhrase = 'weird/weirding';
