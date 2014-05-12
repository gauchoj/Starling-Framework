// -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- 
// 
//  Version: MPL 1.1/GPL 2.0/LGPL 2.1
// 
//  The contents of this file are subject to the Mozilla Public License Version
//  1.1 (the "License"); you may not use this file except in compliance with
//  the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
// 
//  Software distributed under the License is distributed on an "AS IS" basis,
//  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
//  for the specific language governing rights and limitations under the
//  License.
// 
//  The Original Code is the Mozilla SMIL module.
// 
//  The Initial Developer of the Original Code is Brian Birtles.
//  Portions created by the Initial Developer are Copyright (C) 2005
//  the Initial Developer. All Rights Reserved.
// 
//  Contributor(s):
//    Brian Birtles <birtles@gmail.com>
// 
//  Alternatively, the contents of this file may be used under the terms of
//  either of the GNU General Public License Version 2 or later (the "GPL"),
//  or the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
//  in which case the provisions of the GPL or the LGPL are applicable instead
//  of those above. If you wish to allow use of your version of this file only
//  under the terms of either the GPL or the LGPL, and not to allow others to
//  use your version of this file under the terms of the MPL, indicate your
//  decision by deleting the provisions above and replace them with the notice
//  and other provisions required by the GPL or the LGPL. If you do not delete
//  the provisions above, a recipient may use your version of this file under
//  the terms of any one of the MPL, the GPL or the LGPL.
// 
// 
//  Ported to ActionScript 3.0 by pis0 (Maiko Stievem - msdraco@gmail.com)

 
 
package starling.animation {
	import starling.errors.AbstractClassError;
	
	
	public class KeySpline {
		
		private const NEWTON_ITERATIONS : uint = 2; // 4
		private const NEWTON_MIN_SLOPE : Number = 0.02; // 0.02
		private const SUBDIVISION_PRECISION : Number = 1; //0.0000001;
		private const SUBDIVISION_MAX_ITERATIONS : int = 1; // 10
		private const kSplineTableSize : uint = 2; // 11
		
		private var kSampleStepSize : Number = 1.0 / Number(kSplineTableSize - 1);
		private var mSampleValues : Vector.<Number> = new Vector.<Number>(kSplineTableSize);
		
		private var mX1 : Number;
		private var mY1 : Number;
		private var mX2 : Number;
		private var mY2 : Number;
		
		static public var ME:KeySpline = new KeySpline();
		
		function KeySpline() {
			if(ME) throw new AbstractClassError();	
		}

		public function init(aX1 : Number, aY1 : Number, aX2 : Number, aY2 : Number) : KeySpline {
			mX1 = aX1;
			mY1 = aY1;
			mX2 = aX2;
			mY2 = aY2;

			if (mX1 != mY1 || mX2 != mY2) {
				calcSampleValues();
			}

			return this;
		}

		public function getSplineValue(aX : Number) : Number {
			if (mX1 == mY1 && mX2 == mY2) {
				return aX;
			}
			return calcBezier(getTForX(aX), mY1, mY2);
		}

		private function getTForX(aX : Number) : Number {
			var intervalStart : Number = 0.0,
				currentSample : Number = mSampleValues[1],
				lastSample : Number = mSampleValues[kSplineTableSize - 1];

			for (; currentSample != lastSample && currentSample <= aX; ++currentSample) {
				intervalStart += kSampleStepSize;
			}
			--currentSample;

			var dist : Number = (aX - currentSample) / ((currentSample + 1) - currentSample),
				guessForT : Number = intervalStart + dist * kSampleStepSize,
				initialSlope : Number = getSlope(guessForT, mX1, mX2);
				
			if (initialSlope >= NEWTON_MIN_SLOPE) {
				return newtonRaphsonIterate(aX, guessForT);
			} else if (initialSlope == 0.0) {
				return guessForT;
			} else {
				return binarySubdivide(aX, intervalStart, intervalStart + kSampleStepSize);
			}
		}

		private function getSlope(aT : Number, aA1 : Number, aA2 : Number) : Number {
			return 3.0 * a(aA1, aA2) * aT * aT + 2.0 * b(aA1, aA2) * aT + c(aA1);
		}

		private function newtonRaphsonIterate(aX : Number, aGuessT : Number) : Number {
			var currentX : Number,
				currentSlope : Number,
				i : uint = 0;			
			for (; i < NEWTON_ITERATIONS; ++i) {
				currentX = calcBezier(aGuessT, mX1, mX2) - aX;
				currentSlope = getSlope(aGuessT, mX1, mX2);
				if (currentSlope == 0.0) {
					return aGuessT;
				}
				aGuessT -= currentX / currentSlope;
			}
			return aGuessT;
		}

		private function binarySubdivide(aX : Number, aA : Number, aB : Number) : Number {
			var currentX : Number,
				currentT : Number,
				i : uint = 0;
			while (Math.abs(currentX) > SUBDIVISION_PRECISION && ++i < SUBDIVISION_MAX_ITERATIONS) {
				currentT = aA + (aB - aA) / 2.0;
				currentX = calcBezier(currentT, mX1, mX2) - aX;
				if (currentX > 0.0) {
					aB = currentT;
				} else {
					aA = currentT;
				}
			}
			return currentT;
		}

		private function calcSampleValues() : void {
			var i : uint = 0;
			for (; i < kSplineTableSize; ++i) {
				mSampleValues[i] = calcBezier(i * kSampleStepSize, mX1, mX2);
			}
		}

		private function calcBezier(aT : Number, aA1 : Number, aA2 : Number) : Number {
			return ((a(aA1, aA2) * aT + b(aA1, aA2)) * aT + c(aA1)) * aT;
		}

		private function a(aA1 : Number, aA2 : Number) : Number {
			return 1.0 - 3.0 * aA2 + 3.0 * aA1;
		}

		private function b(aA1 : Number, aA2 : Number) : Number {
			return 3.0 * aA2 - 6.0 * aA1;
		}

		private function c(aA1 : Number) : Number {
			return 3.0 * aA1;
		}
		
	}
}
