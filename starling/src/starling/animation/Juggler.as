// =================================================================================================
//
//	Starling Framework
//	Copyright 2011 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.animation
{
	import starling.core.starling_internal;
	import starling.events.Event;
	import starling.events.EventDispatcher;

    /** The Juggler takes objects that implement IAnimatable (like Tweens) and executes them.
     * 
     *  <p>A juggler is a simple object. It does no more than saving a list of objects implementing 
     *  "IAnimatable" and advancing their time if it is told to do so (by calling its own 
     *  "advanceTime"-method). When an animation is completed, it throws it away.</p>
     *  
     *  <p>There is a default juggler available at the Starling class:</p>
     *  
     *  <pre>
     *  var juggler:Juggler = Starling.juggler;
     *  </pre>
     *  
     *  <p>You can create juggler objects yourself, just as well. That way, you can group 
     *  your game into logical components that handle their animations independently. All you have
     *  to do is call the "advanceTime" method on your custom juggler once per frame.</p>
     *  
     *  <p>Another handy feature of the juggler is the "delayCall"-method. Use it to 
     *  execute a function at a later time. Different to conventional approaches, the method
     *  will only be called when the juggler is advanced, giving you perfect control over the 
     *  call.</p>
     *  
     *  <pre>
     *  juggler.delayCall(object.removeFromParent, 1.0);
     *  juggler.delayCall(object.addChild, 2.0, theChild);
     *  juggler.delayCall(function():void { doSomethingFunny(); }, 3.0);
     *  </pre>
     * 
     *  @see Tween
     *  @see DelayedCall 
     */
    public class Juggler implements IAnimatable
    {
        private var mObjects:Vector.<IAnimatable>;
        private var mElapsedTime:Number;
		private var _jugglerIndex:int = -1;
        
        /** Create an empty juggler. */
        public function Juggler()
        {
            mElapsedTime = 0;
            mObjects = new <IAnimatable>[];
        }

        /** Adds an object to the juggler. */
        public function add(object:IAnimatable):void
        {
            if (object && object.jugglerIndex == -1) 
            {
                object.jugglerIndex = mObjects.push(object) - 1;
            
                var dispatcher:EventDispatcher = object as EventDispatcher;
                if (dispatcher) dispatcher.addEventListener(Event.REMOVE_FROM_JUGGLER, onRemove);
            }
        }
        
        /** Determines if an object has been added to the juggler. */
        public function contains(object:IAnimatable):Boolean
        {
            return object.jugglerIndex !== -1; //mObjects.indexOf(object) != -1;
        }
        
        /** Removes an object from the juggler. */
        public function remove(object:IAnimatable):void
        {
            if (object == null) return;
			
			var index:int = object.jugglerIndex;// mObjects.indexOf(object);
			object.jugglerIndex = -1;
			
            var dispatcher:EventDispatcher = object as EventDispatcher;
            if (dispatcher) dispatcher.removeEventListener(Event.REMOVE_FROM_JUGGLER, onRemove);

            if (index > -1) {
				if (index < mObjects.length && mObjects[index] == object) {
					mObjects[index] = null;
				}else {
					index = mObjects.indexOf(object);
					mObjects[index] = null;
				}
			}
			
        }
        
        /** Removes all tweens with a certain target. */
        public function removeTweens(target:Object):void
        {
            if (target == null) return;
            
			var len:int = mObjects.length - 1;
            for (var i:int=len; i>=0; --i)
            {
                var tween:Tween = mObjects[i] as Tween;
                if (tween && tween.target == target)
                {
					tween.jugglerIndex = -1;
                    tween.removeEventListener(Event.REMOVE_FROM_JUGGLER, onRemove);
                    mObjects[i] = null;
                }
            }
        }
        
        /** Figures out if the juggler contains one or more tweens with a certain target. */
        public function containsTweens(target:Object):Boolean
        {
            if (target == null) return false;
            var len:int = mObjects.length - 1;
            for (var i:int=len; i>=0; --i)
            {
                var tween:Tween = mObjects[i] as Tween;
                if (tween && tween.target == target) return true;
            }
            
            return false;
        }
        
        /** Removes all objects at once. */
        public function purge():void
        {
            var i:int;
			var dispatcher:EventDispatcher;
			var object:IAnimatable;
			// the object vector is not purged right away, because if this method is called 
            // from an 'advanceTime' call, this would make the loop crash. Instead, the
            // vector is filled with 'null' values. They will be cleaned up on the next call
            // to 'advanceTime'.
            
            for (i=mObjects.length-1; i>=0; --i)
            {
				object = mObjects[i];
                dispatcher = object as EventDispatcher;
                if (dispatcher) {
					dispatcher.removeEventListener(Event.REMOVE_FROM_JUGGLER, onRemove);
				}
				object.jugglerIndex = -1;
                mObjects[i] = null;
            }
        }
        
        /** Delays the execution of a function until <code>delay</code> seconds have passed.
         *  This method provides a convenient alternative for creating and adding a DelayedCall
         *  manually.
         *
         *  <p>To cancel the call, pass the returned 'IAnimatable' instance to 'Juggler.remove()'.
         *  Do not use the returned IAnimatable otherwise; it is taken from a pool and will be
         *  reused.</p> */
        public function delayCall(call:Function, delay:Number, ...args):DelayedCall
        {
            if (call == null) return null;
            
            var delayedCall:DelayedCall = new DelayedCall(call, delay, args);
            //var delayedCall:DelayedCall = DelayedCall.starling_internal::fromPool(call, delay, args);
            delayedCall.addEventListener(Event.REMOVE_FROM_JUGGLER, onPooledDelayedCallComplete);
            add(delayedCall);

            return delayedCall; 
        }

        //public function repeatCall(call:Function, interval:Number, repeatCount:int=0, ...args):DelayedCall
        //{
            //if (call == null) return null;
            //
            //var delayedCall:DelayedCall = DelayedCall.starling_internal::fromPool(call, interval, args);
            //delayedCall.repeatCount = repeatCount;
            ////delayedCall.addEventListener(Event.REMOVE_FROM_JUGGLER, onPooledDelayedCallComplete);
            //add(delayedCall);
            //
            //return delayedCall;
        //}
        
        private function onPooledDelayedCallComplete(event:Event):void
        {
			event.target.removeEventListener(Event.REMOVE_FROM_JUGGLER, onRemove);
			remove(event.target as IAnimatable);
            //DelayedCall.starling_internal::toPool(event.target as DelayedCall);
        }
        
        /** Utilizes a tween to animate the target object over <code>time</code> seconds. Internally,
         *  this method uses a tween instance (taken from an object pool) that is added to the
         *  juggler right away. This method provides a convenient alternative for creating 
         *  and adding a tween manually.
         *  
         *  <p>Fill 'properties' with key-value pairs that describe both the 
         *  tween and the animation target. Here is an example:</p>
         *  
         *  <pre>
         *  juggler.tween(object, 2.0, {
         *      transition: Transitions.EASE_IN_OUT,
         *      delay: 20, // -> tween.delay = 20
         *      x: 50      // -> tween.animate("x", 50)
         *  });
         *  </pre> 
         *
         *  <p>To cancel the tween, call 'Juggler.removeTweens' with the same target, or pass
         *  the returned 'IAnimatable' instance to 'Juggler.remove()'. Do not use the returned
         *  IAnimatable otherwise; it is taken from a pool and will be reused.</p> */
        public function tween(target:Object, time:Number, properties:Object):IAnimatable
        {
           
            var tween:Tween = create(target, time, properties);
			tween.addEventListener(Event.REMOVE_FROM_JUGGLER, onPooledTweenComplete);
            add(tween);
            return tween;
        }
		
		public function create(target:Object, time:Number, properties:Object):Tween
		{
			var property:String;
			var value:Object;
			var tween:Tween = Tween.starling_internal::fromPool(target, time);
            
            for (property in properties)
            {
                value = properties[property];
                
                if (tween.hasOwnProperty(property))
                    tween[property] = value;
                else if (target.hasOwnProperty(property))
                    tween.animate(property, value as Number);
                else
                    throw new ArgumentError("Invalid property: " + property);
            }
			
			return tween;
			
		}
        
        private function onPooledTweenComplete(event:Event):void
        {
			event.target.removeEventListener(Event.REMOVE_FROM_JUGGLER, onPooledTweenComplete);
            Tween.starling_internal::toPool(event.target as Tween);
        }
        
        /** Advances all objects by a certain time (in seconds). */
        public function advanceTime(time:Number):void
        {   
            var object:IAnimatable;
			var numObjects:int = mObjects.length;
            var currentIndex:int = 0;
            var i:int;
            
            mElapsedTime += time;
            if (numObjects == 0) return;
            
            // there is a high probability that the "advanceTime" function modifies the list 
            // of animatables. we must not process new objects right now (they will be processed
            // in the next frame), and we need to clean up any empty slots in the list.
            
            for (i=0; i<numObjects; ++i)
            {
                object = mObjects[i];
                if (object)
                {
                    // shift objects into empty slots along the way
                    if (currentIndex != i) 
                    {
                        mObjects[currentIndex] = object;
						
                        mObjects[i] = null;
                    }
					
                    object.jugglerIndex = currentIndex;
                    object.advanceTime(time);
					
                    ++currentIndex;
                }
            }
            
            if (currentIndex != i)
            {
                numObjects = mObjects.length; // count might have changed!
                
                while (i < numObjects) {
                    mObjects[int(currentIndex++)] = mObjects[int(i++)];
				}
                mObjects.length = currentIndex;
            }
        }
		
		/* INTERFACE starling.animation.IAnimatable */
		
		public function get jugglerIndex():int {
			return _jugglerIndex;
		}
		
		public function set jugglerIndex(value:int):void {
			_jugglerIndex = value;
		}
        
        private function onRemove(event:Event):void
        {
            remove(event.target as IAnimatable);
            
            var tween:Tween = event.target as Tween;
            if (tween && tween.isComplete)
                add(tween.nextTween);
        }
        
        /** The total life time of the juggler (in seconds). */
        public function get elapsedTime():Number { return mElapsedTime; }
 
        /** The actual vector that contains all objects that are currently being animated. */
        protected function get objects():Vector.<IAnimatable> { return mObjects; }
    }
}
