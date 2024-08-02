#charset "us-ascii"
//
// dynamicVocab.t
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

dynamicVocabPreinit: PreinitObject
	execute() {
		forEachInstance(VocabCfg, { x: x.initVocabCfg() });
	}
;

class VocabProps: object
	props = static [
		&noun, &adjective, &plural, &adjApostS, &literalAdjective
	]

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

/*
	// See if the given word is defined in the given object's prop.
	// Example:  _hasWord('foo', pebble, &adjective) to see if the
	// pebble has "foo" in its adjective list.
	_hasWord(str, obj, prop) {
		if(obj.(prop) == nil) return(nil);
		return(obj.(prop).indexOf(str) != nil);
	}
*/
;

// Class for changes to vocabulary objects.
// The arg to the constructor should be a standard t3 vocabWords string,
// like you'd use in a Thing's declaration.
class VocabCfg: VocabProps
	weakTokens = nil

	init = nil

	construct(v?) { if(v != nil) parseVocabWords(v); }

	initVocabCfg() {
		if(vocabWords == nil)
			return;
		parseVocabWords(vocabWords);
	}

	_debugVocab() {
		aioSay('\n<<toString(self)>>:\n ');
		getPropList().forEach(function(o) {
			if(!propDefined(o, PropDefDirectly))
				return;
			aioSay('\n\t<<toString(o)>>
				= <<toString(self.(o))>>\n ');
		});
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

		foreach(local p in modList)
			self.(p) = self.(p).getUnique();
	}
;

class DynamicVocab: object
	_vocabCfgs = nil

	_addVocabCfg(cfg) {
		if(_vocabCfgs == nil)
			_vocabCfgs = new Vector();

		if(_vocabCfgs.indexOf(cfg) != nil)
			return(nil);

		_vocabCfgs.append(cfg);

		return(true);
	}

	_removeVocabCfg(cfg) {
		local idx;

		if(_vocabCfgs == nil)
			return(nil);
		if((idx = _vocabCfgs.indexOf(cfg)) == nil)
			return(nil);
		_vocabCfgs.removeElementAt(idx);
		return(true);
	}

	addVocab(cfg) {
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		if(!_addVocabCfg(cfg))
			return(nil);

		cfg.applyTo(self);

		return(true);
	}

	removeVocab(cfg) {
		if((cfg == nil) || !cfg.ofKind(VocabCfg))
			return(nil);

		if(!_removeVocabCfg(cfg))
			return(nil);

		cfg.removeFrom(self);

		return(true);
	}

	hasVocab(prop, v) {
		// Easy case:  the value in our property.
		if((self.(prop) != nil) && (self.(prop).indexOf(v) != nil)) {
			return(true);
		}

		if(_vocabCfgs == nil) {
			return(nil);
		}

		return(_vocabCfgs.subset({ x: (x.(prop) != nil)
			&& (x.(prop).indexOf(v) != nil) }).length > 0);
	}

;
