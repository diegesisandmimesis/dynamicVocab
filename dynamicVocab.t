#charset "us-ascii"
//
// dynamicVocab.t
//
//	A TADS3/adv3 module enabling dynamic vocabulary on objects.
//
//	The goal is to provide mechanisms for reliably tweaking the
//	vocabulary of objects at runtime, specific when there's a need
//	for more custimization than you can get from ThingState.
//
//	This module only covered the low-level mechanics of adjusting
//	the vocabulary.  Integration of triggers, events, and other
//	methods of programmatically deciding when to make the change will
//	be handled in another module.
//
//
// USAGE
//
//	First, add DynamicVocab to the superclass list of the object
//	whose vocabulary will be changed.
//
//		// Declare an object whose vocabulary can be updated.
//		pebble: Thing, DynamicVocab '(small) (round) pebble' 'pebble'
//			"A small, round pebble. "
//		;
//
//	Now declare one or more VocabCfg instances, defining vocabWords
//	on them using the same syntax vocabulary is declared on a Thing:
//
//		// Declare the dynamic part of the vocabulary.
//		alien: VocabCfg '(alien) artifact';
//
//	Having done this, you can now add the additional vocabulary to
//	the object with:
//
//		// Add the "alien" vocabulary to the pebble.
//		pebble.addVocab(alien);
//
//	Now the noun phrase "artifact" and "alien artifact" will resolve
//	to the pebble (when it's in context).
//
//	You can remove the additional vocabulary with:
//
//		// Remove the "alien" vocabulary to the pebble.
//		pebble.removeVocab(alien);
//
//	Vocabulary will only be removed if it would not otherwise be
//	on the object.  So for example if you define multiple VocabCfgs
//	with overlapping vocabulary removing one won't remove the duplicate
//	words.  For example:
//
//		// Create a couple VocabCfg instances.
//		alien = new VocabCfg('(alien) artifact');
//		weird = new VocabCfg('(weird) artifact');
//
//		// Add them to the pebble.
//		pebble.addVocab(alien);		// >X ALIEN ARTIFACT now works
//		pebble.addVocab(weird);		// >X WEIRD ARTIFACT now works
//
//		// Remove the "weird" vocabulary.
//		pebble.removeVocab(alien);
//
//	In the above example after the last line pebble will still have
//	the noun "artifact" defined on it;  removeVocab(alien) will have only
//	removed the adjective "alien".
//
//
#include <adv3.h>
#include <en_us.h>

#include "dynamicVocab.h"

// Module ID for the library
dynamicVocabModuleID: ModuleID {
        name = 'Dynamic Vocab Library'
        byline = 'Diegesis & Mimesis'
        version = '1.0'
        listingOrder = 99
}

// Preinit object.  We just ping all the VocabCfg instances.
dynamicVocabPreinit: PreinitObject
	execute() {
		forEachInstance(VocabCfg, { x: x.initVocabCfg() });
	}
;

// Abstract class defining only the vocab properties we care about
// and how to add and remove them from objects.
class VocabProps: object
	// List of vocabulary properties we care about.
	props = static [
		&noun, &adjective, &plural, &adjApostS, &literalAdjective
	]

	// Add our vocabulary to the given object.
	applyTo(obj) {
		props.subset({ x: self.propDefined(x, PropDefDirectly) })
			.forEach({ x: cmdDict.addWord(obj, self.(x), x) });
	}

	// Remove our vocabulary from the given object.
	// Commentary:
	//	First we get a list of all the properties in the prop list
	//	that we have defined directly.
	//	The we iterate over each of them.
	//	Each of these properties is a list, and we get a subset
	//	of that list containing only the elements that ARE NOT
	//	defined in the same property on the object being reverted.
	//	We then remove each element of that subset from the
	//	object's property.
	removeFrom(obj) {
		props.subset({ x: self.propDefined(x, PropDefDirectly) })
			.forEach(function(x) {
				self.(x).subset({ o: !obj.hasVocab(x, o) })
				.forEach({ o: cmdDict.removeWord(obj, o, x) });
			});
	}
;

// Class for changes to vocabulary objects.
// The arg to the constructor should be a standard t3 vocabWords string,
// like you'd use in a Thing's declaration.
class VocabCfg: VocabProps
	// By default we create an Unthing that shares our vocabulary.
	// This is so the parser doesn't complain about a word not being
	// needed in the game when our vocabulary isn't on any objects.
	useUnthing = true

	// Class to use for the Unthing if useUnthing (above) is true.
	dynamicVocabUnthingClass = DynamicVocabUnthing

	// Placeholder;  this is the only one of the vocabulary properties
	// we care about that ISN'T a grammatical reserved keyword.
	weakTokens = nil

	construct(v?) {
		if(v != nil) vocabWords = v;
		initVocabCfg();
	}

	// Preinit/construct-time initialization.
	initVocabCfg() {
		// If we don't have a vocabWords, we have nothing to do.
		if(vocabWords == nil)
			return;

		// Parse the vocabWords.  This is mostly equivalent to
		// initializeVocabWith() with the exception that we
		// don't add anything to the cmdDict here.
		parseVocabWords(vocabWords);

		// Create the Unthing for our vocabulary, if we're doing so.
		createUnthing();
	}

	createUnthing() {
		local obj;

		if(useUnthing != true) return;

		obj = dynamicVocabUnthingClass.createInstance();
		obj.initializeVocabWith(vocabWords);
		obj.parentVocabCfg = self;
	}

	// Get the length of the next bit of string to parse.
	tokenLen(str) {
		local r;

		if(str.startsWith('"'))
			r = str.find('"', 2);
		else
			r = rexMatch('<^space|star|/>*', str);

		if(r == nil)
			r = str.length();

		return(r);
	}

	// Check to see if the arg is a weak token declaration.
	isWeak(v) { return(v.startsWith('(') && v.endsWith(')')); }

	// Add a weak token to ourselves.
	addWeak(str) {
		str = str.substr(2, str.length() - 2);

		if(weakTokens == nil)
			weakTokens = [];

		weakTokens += str;

		return(str);
	}

	// Parse a bit of a vocabWords string.
	// p is the current part of speech we're working on.
	// cur is the current string
	// modList is a list of stuff we want to add when we're done
	// Return value is an array, first element is the part of speech
	// being worked on when we're done, second element is the
	// part of cur left to work on.
	parseBit(p, cur, modList) {
		local part;

		part = p;

		if(isWeak(cur))
			cur = addWeak(cur);

		if(cur.startsWith('"')) {
			if(cur.endsWith('"'))
				cur = cur.substr(2, cur.length() - 2);
			else
				cur = cur.substr(2);

			part = &literalAdjective;
		} else if(cur.endsWith('\'s')) {
			part = &adjApostS;

			cur = cur.substr(1, cur.length() - 2);
		}

		if(self.(part) == nil)
			self.(part) = [cur];
		else
			self.(part) += cur;

		//cmdDict.addWord(self, cur, part);

		if(cur.endsWith('.')) {
			local abbr;

			abbr = cur.substr(1, cur.length() - 1);
			self.(part) += abbr;
			//cmdDict.addWord(self, abbr, part);
		}

		if(modList.indexOf(part) == nil)
			modList += part;

		return([ p, cur ]);
	}

	// Mostly a initializeVocabWith() workalike, with the exception
	// that we don't add anything to cmdDict.
	parseVocabWords(str) {
		local cur, len, modList, p, v;

		modList = [];
		p = &adjective;

		while(str != '') {
			len = tokenLen(str);

			if(len != 0) {
				cur = str.substr(1, len);

				if((p == &adjective) && ((len == str.length())
					|| (str.substr(len + 1, 1) != ' '))) {
					p = &noun;
				}

				if(cur != '-') {
					v = parseBit(p, cur, modList);

					p = v[1];
					cur = v[2];
				}
			}

			if(len + 1 < str.length()) {
				switch(str.substr(len + 1, 1)) {
					case ' ':
						break;
					case '*':
						p = &plural;
						break;
					case '/':
						p = &noun;
						break;
				}

				str = str.substr(len + 2);

				if((len = rexMatch('<space>+', str)) != nil)
					str = str.substr(len + 1);
			} else {
				break;
			}
		}

		modList.forEach({ x: self.(x) = self.(x).getUnique() });
	}
;

// Mixin class for objects that want to use dynamic vocabulary.
class DynamicVocab: object
	// This will hold all of our active VocabCfgs.
	_vocabCfgs = nil

	// Add a VocabCfg instance to our list, if it's not already on it.
	_addVocabCfg(cfg) {
		if(_vocabCfgs == nil)
			_vocabCfgs = new Vector();

		if(_vocabCfgs.indexOf(cfg) != nil)
			return(nil);

		_vocabCfgs.append(cfg);

		return(true);
	}

	// Remove a VocabCfg instance from our list, if it's there.
	_removeVocabCfg(cfg) {
		local idx;

		if(_vocabCfgs == nil)
			return(nil);
		if((idx = _vocabCfgs.indexOf(cfg)) == nil)
			return(nil);
		_vocabCfgs.removeElementAt(idx);
		return(true);
	}

	// Add a VocabCfg instance.
	addVocab(cfg) {
		// Make sure the arg is valid.
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		// Remember this VocabCfg.  This will fail if it's
		// already on our list.
		if(!_addVocabCfg(cfg))
			return(nil);

		// Apply the vocabulary changes.
		cfg.applyTo(self);

		return(true);
	}

	// Remove a VocabCfg instance.
	removeVocab(cfg) {
		// Make sure the arg is valid.
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		// Forget about this VocabCfg.  This will fail if it
		// isn't on our list.
		// IMPORTANT:  We have to do this BEFORE VocabCfg.removeFrom()
		// 	is called, because it checks the list as part of
		//	figuring out what to remove, and we need to be
		//	off the list before that happens.
		if(!_removeVocabCfg(cfg))
			return(nil);

		// Apply the vocabulary changes.
		cfg.removeFrom(self);

		return(true);
	}

	// Check to see if the given prop on this object includs the
	// word v.
	// IMPORTANT:  This is called from VocabCfg.removeFrom(), and it
	//	needs to be called AFTER the VocabCfg instance being removed
	//	is taken off the object's _vocabCfgs list.  This is because
	//	we check to see if the word in question is in any other
	//	VocabCfg's vocabulary and we don't remove the vocabulary
	//	if it is.  And if the VocabCfg being removed is still on
	//	the list then of course its vocabulary would be found.
	hasVocab(prop, v) {
		// Easy case:  the value is in our property.
		if((self.(prop) != nil) && (self.(prop).indexOf(v) != nil))
			return(true);

		// Make sure we have a VocabCfg list.
		if(_vocabCfgs == nil)
			return(nil);

		// Check our VocabCfg list for anyone that has the
		// word we're looking for in the property we're checking.
		// As noted above, the VocabCfg being removed has to
		// be off this list before we get here or we're
		// guaranteed to get a match.
		return(_vocabCfgs.subset({ x: (x.(prop) != nil)
			&& (x.(prop).indexOf(v) != nil) }).length > 0);
	}
;

// Unthing class.
class DynamicVocabUnthing: Unthing parentVocabCfg = nil;
