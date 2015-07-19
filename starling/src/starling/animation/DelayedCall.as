// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
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

    /** A DelayedCall allows you to execute a method after a certain time has passed. Since it 
     *  implements the IAnimatable interface, it can be added to a juggler. In most cases, you 
     *  do not have to use this class directly; the juggler class contains a method to delay
     *  calls directly. 
     * 
     *  <p>DelayedCall dispatches an Event of type 'Event.REMOVE_FROM_JUGGLER' when it is finished,
     *  so that the juggler automatically removes it when its no longer needed.</p>
     * 
     *  @see Juggler
     */ 
    public class DelayedCall 
	extends EventDispatcher 
//	implements IPooledAnimatable
	implements IAnimatable
    {
        private var mCurrentTime:Number;
        private var mTotalTime:Number;
        private var mCall:Function;
        private var mArgs:Array;
        private var mRepeatCount:int;
        
        /** Creates a delayed call. */
        public function DelayedCall(call:Function, delay:Number, args:Array=null)
        {
            reset(call, delay, args);
        }
        
        /** Resets the delayed call to its default values, which is useful for pooling. */
        public function reset(call:Function, delay:Number, args:Array=null):DelayedCall
        {
            mCurrentTime = 0;
            mTotalTime = Math.max(delay, 0.0001);
            mCall = call;
            mArgs = args;
            mRepeatCount = 1;
//			_jugglerIndex = -1;
//			pooled = false;
            
            return this;
        }
        
        /** @inheritDoc */
        public function advanceTime(time:Number):void
        {
            var previousTime:Number = mCurrentTime;
            mCurrentTime += time;

            if (mCurrentTime > mTotalTime)
                mCurrentTime = mTotalTime;
            
            if (previousTime < mTotalTime && mCurrentTime >= mTotalTime)
            {                
                if (mRepeatCount == 0 || mRepeatCount > 1)
                {
					// TODO watch
                    if (mCall)
					{
						mCall.apply(null, mArgs);
					}
                    
                    if (mRepeatCount > 0) mRepeatCount -= 1;
                    mCurrentTime = 0;
					
					advanceTime((previousTime + time) - mTotalTime);
					
//					// TODO watch
//					if (!pooled)
//					// 
//					{
//	                    advanceTime((previousTime + time) - mTotalTime);
//					}
                }
                else
                {
                    // save call & args: they might be changed through an event listener
                    var call:Function = mCall;
                    var args:Array = mArgs;
                    
                    // in the callback, people might want to call "reset" and re-add it to the
                    // juggler; so this event has to be dispatched *before* executing 'call'.
                    dispatchEventWith(Event.REMOVE_FROM_JUGGLER);
                    call.apply(null, args);
                }
            }
        }

        /** Advances the delayed call so that it is executed right away. If 'repeatCount' is
          * anything else than '1', this method will complete only the current iteration. */
        public function complete():void
        {
            var restTime:Number = mTotalTime - mCurrentTime;
            if (restTime > 0) advanceTime(restTime);
        }
        
        /** Indicates if enough time has passed, and the call has already been executed. */
        public function get isComplete():Boolean 
        { 
            return mRepeatCount == 1 && mCurrentTime >= mTotalTime; 
        }
        
        /** The time for which calls will be delayed (in seconds). */
        public function get totalTime():Number { return mTotalTime; }
        
        /** The time that has already passed (in seconds). */
        public function get currentTime():Number { return mCurrentTime; }
        
        /** The number of times the call will be repeated. 
         *  Set to '0' to repeat indefinitely. @default 1 */
        public function get repeatCount():int { return mRepeatCount; }
        public function set repeatCount(value:int):void { mRepeatCount = value; }
        
        // delayed call pooling
        
//		static private const POOLING: Boolean = false;
//		private static var sPool:LinkedList = new LinkedList();
//		private static var hits: int = 0;
//		private static var misses: int = 0;
//		static private const POOL_SIZE: int = 200;
		
        /** @private */
        starling_internal static function fromPool(call:Function, delay:Number, args:Array=null):DelayedCall
        {
//			if (POOLING)
//			{
//	            if (sPool.size>=POOL_SIZE)
//				{
//					var delayedCall:DelayedCall = DelayedCall(sPool.poll());
////					if (!delayedCall.pooled) throw new AssukarError();
//					hits++;
////					delayedCall.pooled = false;
//					delayedCall._jugglerIndex = -1;
//					return delayedCall.reset(call, delay, args);
//				}
//	            else 
//				{
//					misses++;
//					if (misses%10==0) log("Tween pool:" + sPool.size + " hits:" + hits + " misses:" + misses + " ratio:" + (hits/(hits+misses)).toFixed(3));
//					return new DelayedCall(call, delay, args);
//				}
//			}
//			else
//			{
				return new DelayedCall(call, delay, args);
//			}
        }
        
        /** @private */
        starling_internal static function toPool(delayedCall:DelayedCall):void
        {
//			if (POOLING)
//			{
////				if (delayedCall.pooled) return;
////				delayedCall.pooled = true;
//				
//	            // reset any object-references, to make sure we don't prevent any garbage collection
//	            delayedCall.mCall = null;
//	            delayedCall.mArgs = null;
//	            delayedCall.removeEventListeners();
//				// in case it changed in the event listener
////				delayedCall.pooled = true;
//				//
//	            sPool.push(delayedCall);
//			}
//			else
//			{
	            delayedCall.mCall = null;
	            delayedCall.mArgs = null;
	            delayedCall.removeEventListeners();
//			}
        }
		
		/* INTERFACE starling.animation.IAnimatable */
		private var _jugglerIndex : int = -1;
		public function get jugglerIndex() : int
		{
			return _jugglerIndex;
		}
		public function set jugglerIndex(value : int) : void
		{
			_jugglerIndex = value;
		}
		
//		/* INTERFACE starling.animation.PooledIAnimatable */
//		private var pooled: Boolean = false;
//		public function pool(): void
//		{
//			DelayedCall.starling_internal::toPool(this);
//		}				
    }
}