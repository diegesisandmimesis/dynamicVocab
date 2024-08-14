#charset "us-ascii"
//
// dynamicVocab.t
//
//	A TADS3/adv3 module enabling dynamic vocabulary on objects.
//
//	The goal is to provide mechanisms for reliably tweaking the
//	vocabulary of objects at runtime, specifically when there's a need
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
//		+alien: VocabCfg '(alien) artifact';
//
//	Having done this, you can now add the additional vocabulary to
//	the object with:
//
//		// Add the "alien" vocabulary to the pebble.
//		pebble.activateVocab(alien);
//
//	Now the noun phrase "artifact" and "alien artifact" will resolve
//	to the pebble (when it's in context).
//
//	You can remove the additional vocabulary with:
//
//		// Remove the "alien" vocabulary to the pebble.
//		pebble.deactivateVocab(alien);
//
//	Vocabulary will only be removed if it would not otherwise be
//	on the object.  So for example if you define multiple VocabCfgs
//	with overlapping vocabulary removing one won't remove the duplicate
//	words.  For example:
//
//		// The base object.
//		pebble: Thing, DynamicVocab '(small) (round) pebble' 'pebble'
//			"A small, round pebble. "
//		;
//		// Create a couple VocabCfg instances.
//		+alien = new VocabCfg('(alien) artifact');
//		+weird = new VocabCfg('(weird) artifact');
//
//		// Add them to the pebble.
//		pebble.activateVocab(alien);	// >X ALIEN ARTIFACT now works
//		pebble.activateVocab(weird);	// >X WEIRD ARTIFACT now works
//
//		// Remove the "alien" vocabulary.
//		pebble.deactivateVocab(alien);
//
//	In the above example after the last line pebble will still have
//	the noun "artifact" defined on it;  deactivateVocab(alien) will have only
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
	// Sorting order
	order = 99

	active = nil

	name = nil

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

		if((location != nil) && location.ofKind(DynamicVocab))
			location.addVocab(self);

		// Parse the vocabWords.  This is mostly equivalent to
		// initializeVocabWith() with the exception that we
		// don't add anything to the cmdDict here.
		parseVocabWords(vocabWords);

		// Create the Unthing for our vocabulary, if we're doing so.
		createUnthing();

		canonicalizeOrder();
	}

	canonicalizeOrder() {
		switch(dataTypeXlat(order)) {
			case TypeSString:
				order = toInteger(order);
				break;
			case TypeInt:
				break;
			default:
				order = 99;
				break;
		}
	}

	createUnthing() {
		local obj;

		if(useUnthing != true) return;

		obj = dynamicVocabUnthingClass.createInstance();
		obj.initializeVocabWith(vocabWords);
		obj.parentVocabCfg = self;
	}

	isActive() { return(active == true); }
	setActive(v) { active = (v ? true : nil); }

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

	_vocabCfgState = nil

	// Flag indicating whether or not the _vocabCfgs are sorted.
	_vocabCfgsSorted = nil

	// Add a VocabCfg instance to our list, if it's not already on it.
	addVocab(cfg) {
		if(_vocabCfgs == nil)
			_vocabCfgs = new Vector();

		if(_checkVocabCfg(cfg))
			return(nil);

		_vocabCfgs.append(cfg);

		// Make sure we re-sort if we want a sorted list.
		_vocabCfgsSorted = nil;

		if(cfg.isActive())
			activateVocab(cfg);

		return(true);
	}
	_checkVocabCfg(cfg) {
		return(_vocabCfgs ? _vocabCfgs.indexOf(cfg) != nil : nil);
	}

	_getVocabCfgState(cfg) {
		return(_vocabCfgState ? _vocabCfgState[cfg] : nil);
	}
	_setVocabCfgState(cfg, v) {
		if(_vocabCfgState == nil)
			_vocabCfgState = new LookupTable();
		_vocabCfgState[cfg] = ((v == true) ? true : nil);
	}

	// Remove a VocabCfg instance from our list, if it's there.
	removeVocab(cfg) {
		local idx;

		if(_vocabCfgs == nil)
			return(nil);
		if((idx = _vocabCfgs.indexOf(cfg)) == nil)
			return(nil);
		_vocabCfgs.removeElementAt(idx);

		deactivateVocab(cfg);

		// NOTE:  We DON'T clear the sorted flag because removing
		//	an element won't un-sort the other elements.

		return(true);
	}

	// Make a VocabCfg instance active.
	activateVocab(cfg) {
		// Make sure the arg is valid.
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		if(!_checkVocabCfg(cfg))
			return(nil);

		// Apply the vocabulary changes.
		cfg.applyTo(self);
		twiddleCfg(cfg, true);

		return(true);
	}

	// Make a VocabCfg active or inactive.
	twiddleCfg(cfg, v) {
		// Change the state on the instance itself.
		cfg.setActive(v);

		// Remember this state.  This is used to detect when
		// the state changes, which means we need to update our
		// vocabulary.
		_setVocabCfgState(cfg, v);
	}

	// Remove a VocabCfg instance.
	deactivateVocab(cfg) {
		// Make sure the arg is valid.
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		if(_getVocabCfgState(cfg) != true)
			return(nil);

		// IMPORTANT:  Must happen before the removeFrom() below.
		twiddleCfg(cfg, nil);

		// Apply the vocabulary changes.
		cfg.removeFrom(self);


		return(true);
	}

	// Go through each VocabCfg instance (that we care about) and
	// check to see if it's active or not.  If this has changed since
	// the last time we checked, we update our vocabulary to reflect
	// the new state.
	syncVocab() {
		local b;

		_vocabCfgs.forEach(function(o) {
			// Current state of this VocabCfg.
			b = o.isActive();

			// If the current state is the same as what we
			// have saved for this instance, we have nothing to do.
			if(_getVocabCfgState(o) == b)
				return;


			// The state has changed, so update our vocab to
			// reflect the current state.
			if(b)
				activateVocab(o);
			else
				deactivateVocab(o);
		});
	}

	// Check to see if the given prop on this object includes the
	// word v.
	// IMPORTANT:  This is called from VocabCfg.removeFrom(), and it
	//	needs to be called AFTER the VocabCfg instance being removed
	//	is marked as inactive.  This is because we go through
	//	the VocabCfg list to see if there is anything that uses
	//	the same vocabulary as the bit that's being removed.  And
	//	if the VocabCfg instance being removed isn't inactive, it
	//	will of course match itself, causing the removal to fail.
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
			&& (x.isActive() == true)
			&& (x.(prop).indexOf(v) != nil) }).length > 0);
	}

	sortVocabCfgs() {
		if(_vocabCfgs == nil) return(nil);
		_vocabCfgs = _vocabCfgs.sort(nil, { a, b: b.order - a.order });
		_vocabCfgsSorted = true;
		return(true);
	}

	getVocabCfg() {
		if(_vocabCfgs == nil)
			return(nil);
		if(_vocabCfgsSorted != true)
			sortVocabCfgs();
		return(_vocabCfgs.valWhich({ x: x.isActive() == true }));
	}
;

// Unthing class.
class DynamicVocabUnthing: Unthing parentVocabCfg = nil;
