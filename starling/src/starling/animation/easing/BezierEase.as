// =================================================================================================
// linear       (0,0,1,1)
// ease         (0.25, 0.1, 0.25, 1.0)
// ease-in      (0.42, 0, 1.0, 1.0)
// ease-out     (0, 0, 0.58, 1.0)
// ease-in-out  (0.42, 0, 0.58, 1.0)
//
//  standard:     (0.4,0,0.2,1)
//  deceleration: (0,0,0.2,1)
//  acceleration: (0.4,0,1,1)
//  sharp:        (0.4,0,0.6,1)

package starling.animation.easing {

import flash.utils.Dictionary;

public class BezierEase {


    // These values are established by empiricism with tests (tradeoff: performance VS precision)
    public static var newtonIterations:uint = 4;
    public static var newtonMinSlope:Number = 0.001;
    public static var subdivisonPrecision:Number = 0.0000001;
    public static var subdivisionIterations:uint = 10;

    // defined in config (common table size = 11)
    private var _splineTableSize:Number;
    private var _sampleStepSize:Number;

    private var _samples:Array;

    // [x1, y1, x2, y2]
    private var _points:Array;

    // Id is only valid for internal reuse.
    private var _id:String;
    private static var _map:Dictionary = new Dictionary(true);

    /**
     * Constructor.
     */
    public function BezierEase() {
    }

    /**
     * Returns the curved value for the ratio.
     * @param percent   percent sent by the Tween engine (ranges 0-1).
     * @return
     */
    public function getRatio(percent:Number):Number {

        if (percent == 0) return 0;
        else if (percent == 1) return 1;

        // Performance: faster variable access for local members.
        var pts:Array = _points;

        // linear
        if (pts[0] == pts[1] && pts[2] == pts[3]) return percent;

        // get T for ratio (x).
        var intervalStart:Number = 0;
        var currentSample:uint = 1;
        var lastSample:uint = _splineTableSize - 1;
        while (currentSample != lastSample && _samples[currentSample] <= percent) {
            intervalStart += _sampleStepSize;
            ++currentSample;
        }
        --currentSample;

        // Interpolate to provide an initial guess for t
        var t:Number = intervalStart + ((percent - _samples[currentSample]) / (_samples[int(currentSample + 1)] - _samples[currentSample])) * _sampleStepSize;

        var initialSlope:Number = getSlope(t, pts[0], pts[2]);
        if (initialSlope == 0) {
        } else if (initialSlope >= newtonMinSlope) {
            // Mostly resolves here for common ranges.
            var len:uint = newtonIterations;
            var currentSlope:Number;
            for (var i:int = 0; i < len; ++i) {
                currentSlope = getSlope(t, pts[0], pts[2]);
                if (currentSlope == 0) break;
                t -= (calcBezier(t, pts[0], pts[2]) - percent) / currentSlope;
            }
        } else {
            // When precision is required...
            t = binarySubdivide(percent, intervalStart, intervalStart + _sampleStepSize, pts[0], pts[2]);
        }
        return calcBezier(t, pts[1], pts[3]);
    }

    /**
     * Setup for the bezier curve.
     * @param x1
     * @param y1
     * @param x2
     * @param y2
     * @param splineTableSize
     * @return
     */
    public function config(x1:Number, y1:Number, x2:Number, y2:Number, splineTableSize:uint = 1):BezierEase {
        x1 = x1 < 0 ? 0 : (x1 > 1 ? 1 : x1);
        x2 = x2 < 0 ? 0 : (x2 > 1 ? 1 : x2);
        if (splineTableSize < 2) splineTableSize = 2;

        _points = [x1, y1, x2, y2];
        _splineTableSize = splineTableSize;
        _sampleStepSize = 1 / (_splineTableSize - 1);

        // Precompute samples table
        _samples = [];
        if (x1 != y1 || x2 != y2) {
            for (var i:int = 0; i < _splineTableSize; ++i) {
                _samples[i] = calcBezier(i * _sampleStepSize, x1, x2);
            }
        }
        return this;
    }

    /**
     * Creates (and stores) a BezierEase based on the provided configuration
     * returns the getRatio() function to use it directly on Starling Tweens calls.
     * @see http://cubic-bezier.com/ to create the curves.
     *
     * @param x1
     * @param y1
     * @param x2
     * @param y2
     * @param id [optional] if specified this id will be used as key internally to retrieve the instance
     *                      later with BezierEase.get()
     * @return
     */
    public static function config(x1:Number, y1:Number, x2:Number, y2:Number, id:String = null):Function {
        x1 = x1 < 0 ? 0 : (x1 > 1 ? 1 : x1);
        x2 = x2 < 0 ? 0 : (x2 > 1 ? 1 : x2);

        if (!id) id = [x1, y1, x2, y2].toString();
        var instance:BezierEase = get(id);
        if (!instance._points) {
            // initialize.
            instance.config(x1, y1, x2, y2);
        }
        return instance.getRatio;
    }

    // Returns x(t) given t, x1, and x2, or y(t) given t, y1, and y2.
    // todo: inline?
    private function calcBezier(t:Number, a1:Number, a2:Number):Number {
        return (((1 - 3 * a2 + 3 * a1) * t + (3 * a2 - 6 * a1)) * t + (3 * a1)) * t;
    }

    // Returns dx/dt given t, x1, and x2, or dy/dt given t, y1, and y2.
    // todo: inline?
    private function getSlope(t:Number, a1:Number, a2:Number):Number {
        return 3 * (1 - 3 * a2 + 3 * a1) * t * t + 2 * (3 * a2 - 6 * a1) * t + (3 * a1);
    }

    // todo: inline?
    private function binarySubdivide(ratio:Number, a:Number, b:Number, x1:Number, x2:Number):Number {
        var currentX:Number, t:Number, i:uint = 0;
        var len:uint = subdivisionIterations;
        var precision:Number = subdivisonPrecision;
        do {
            t = a + (b - a) / 2;
            currentX = calcBezier(t, x1, x2) - ratio;
            if (currentX > 0) {
                b = t;
            } else {
                a = t;
            }
        } while (Math.abs(currentX) > precision && ++i < len);
        return t;
    }

    /**
     * Dispose the stored instace if the ::id is found.
     * @param id
     */
    public static function dispose(id:String):void {
        if (id && _map[id]) BezierEase(_map[id]).dispose();
    }

    /**
     * BezierEase created with BezierEase.config() stores instances based on provided id for
     * reuse.
     * @param id
     * @return
     */
    public static function get(id:String):BezierEase {
        if (!id) return null;
        if (!_map[id]) {
            _map[id] = new BezierEase();
            _map[id]._id = id;
        }
        return _map[id];
    }

    public function dispose():void {
        if (_id) delete _map[_id];
        _samples = null;
        _points = null;
        _id = null;
    }

    public function get id():String {
        return _id;
    }
}
}
