
package axl.utils
{
	import flash.display.Stage;
	import flash.events.Event;
	import flash.utils.getTimer;

	public class AO {
		//general
		private static var STG:Stage;
		private static var curFrame:int;
		private static var frameTime:int;
		private static var prevFrame:int;
		
		private static var animObjects:Vector.<AO> = new Vector.<AO>();
		private static var easings:Easings = new Easings();
		private static var defaultEasing:Function = easings.easeOutQuad;
		private static var numObjects:int=0;
		
		//internal
		private var propNames:Vector.<String>;
		private var propStartValues:Vector.<Number>;
		private var propEndValues:Vector.<Number>;
		private var propDifferences:Vector.<Number>;
		private var eased:Vector.<Vector.<Number>>;
		private var remains:Vector.<Number>;
		private var prevs:Vector.<Number>;
		
		private var numProperties:int=0
		private var duration:int=0;
		private var passedTotal:int=0;
		private var passedRelative:int=0;
		private var direction:int=1;
		private var cur:Number=0;
	
		private var updateFunction:Function;
		private var getValue:Function;
		private var isPlaying:Boolean;
		private var isSetup:Boolean;
		private var id:int;
		
		// applying anytime
		public var yoyo:Boolean=false;
		public var cycles:int=1;
		public var subject:Object;
		
		public var onStartArgs:Array;
		public var onUpdateArgs:Array;
		public var onYoyoHalfArgs:Array;
		public var onCycleArgs:Array;
		public var onCompleteArgs:Array;
		
		public var onStart:Function;
		public var onUpdate:Function;
		public var onYoyoHalf:Function;
		public var onCycle:Function;
		public var onComplete:Function;
		public var destroyOnComplete:Boolean = true;
		
		// applying only before start
		private var uIncremental:Boolean=false;
		private var uFrameBased:Boolean=true;
		private var uPrecalculateFrameValues:Boolean=true;
		private var uProps:Object;
		private var uSeconds:Number;
		private var uEasing:Function = defaultEasing;
		
		// live copy 
		private var incremental:Boolean=false;
		private var frameBased:Boolean=true;
		private var precalculateFrameValues:Boolean;
		private var props:Object;
		private var easing:Function;
		
		public function destroy(executeOnComplete:Boolean=false):void
		{
			//# U.log('[AO][destroy]'+ subject);
			removeFromPool();
			numProperties = duration = passedTotal = passedRelative = cur = uSeconds = 0;
			propStartValues = propEndValues = propDifferences = remains =  prevs = null;
			propNames = null;
			eased = null;
			direction = cycles = 1;
			subject = props = uProps = null;
			onUpdateArgs = onYoyoHalfArgs = onCycleArgs = null;
			updateFunction = getValue = easing = uEasing = onUpdate = onYoyoHalf = onCycle = null;
			
			if(executeOnComplete && (onComplete != null))
				onComplete.apply(null, onCompleteArgs);
			
			onCompleteArgs = null;
			onComplete = null;
		}
		
		public function AO(subject:Object, seconds:Number, properties:Object) {
			if(STG == null)
				throw new Error("[AO]Stage not set up!");
			uSeconds = seconds;
			uProps = properties;
			this.subject = subject;
		}
		
		private function setUp():void
		{
			//# U.log('[AO][setup]' + subject);
			prepareCommon();
			if(incremental) prepareIncremental();
			else prepareAbsolute();
			
			if(frameBased) prepareFrameBased();
			else prepareTimeBased();
			isSetup = true;
		}
		
		private function prepareCommon():void
		{
			if(propNames) propNames.length = 0; else propNames = new Vector.<String>();
			if(propStartValues) propStartValues.length = 0; else propStartValues = new Vector.<Number>();
			if(propEndValues) propEndValues.length = 0; else propEndValues = new Vector.<Number>();
			if(propDifferences) propDifferences.length = 0; else propDifferences = new Vector.<Number>();
			
			numProperties = duration = passedTotal = passedRelative = cur = 0;
			
			props = uProps;
			easing = uEasing || defaultEasing;
			precalculateFrameValues = uPrecalculateFrameValues;
			frameBased = uFrameBased;
			incremental = uIncremental;
			
			for(var s:String in props)
			{
				if(subject.hasOwnProperty(s) && !isNaN(subject[s]) && !isNaN(props[s]))
					propNames[numProperties++] = s;
				else if(this.hasOwnProperty(s))
					this[s] = props[s];
				else throw new ArgumentError("[AO]" + subject + " Invalid property '"+s+"' or value: " + props[s]);  
			}
		}
		
		// ----------------------------------------- PREPARE ----------------------------------- //
		private function prepareIncremental():void
		{
			if(prevs) prevs.length = 0; else prevs = new Vector.<Number>();
			if(remains) remains.length = 0; else remains = new Vector.<Number>();
			updateFunction = updateIncremental;
			for(var i:int=0; i<numProperties;i++)
			{
				propDifferences[i] = props[propNames[i]];
				propStartValues[i] = subject[propNames[i]];
				propEndValues[i] = propStartValues[i] + propDifferences[i];
				remains[i] = propDifferences[i];
				prevs[i] = propStartValues[i];
			}
		}
		
		private function prepareAbsolute():void
		{
			updateFunction = updateAbsolute;
			for(var i:int=0; i<numProperties;i++)
			{
				propStartValues[i] = subject[propNames[i]];
				propEndValues[i] = props[propNames[i]];
				propDifferences[i] = props[propNames[i]] - subject[propNames[i]];
			}
		}
		
		private function prepareTimeBased():void {
			duration  =  (uSeconds * 1000); 
			getValue = getValueLive;
		}
		private function prepareFrameBased():void
		{
			duration = Math.ceil(STG.frameRate * uSeconds) // no frames
			
			if(!precalculateFrameValues)
				getValue = getValueLive;
			else 
			{
				getValue = getValueEased;
				eased = new Vector.<Vector.<Number>>(numProperties,true);
				var i:int, j:int;
				for(i=0;i<numProperties;i++)
				{
					eased[i] = new Vector.<Number>(duration,true);
					for(j=0; j < duration;j++) 
						eased[i][j] = easing(j, propStartValues[i], propDifferences[i], duration);
				}
			}
		}
		// ----------------------------------------- UPDATE ------------------------- //
		protected function tick(milsecs:int):void
		{
			passedTotal += frameBased ? 1 : milsecs;
			passedRelative = (direction < 0) ? (duration - passedTotal) : passedTotal;
			if(passedTotal >= duration) 
			{
				passedTotal = duration;
				passedDuration();
			}
			else
			{
				updateFunction();
				if(onUpdate is Function)
					onUpdate.apply(null, onUpdateArgs);
			}
		}
				
		//absolute
		private function updateAbsolute():void
		{
			for(var i:int=0;i<numProperties;i++)
				subject[propNames[i]] = getValue(i);
		}
		
		//inctemental
		private function updateIncremental():void
		{
			for(var i:int=0;i<numProperties;i++)
			{
				cur = getValue(i);
				var add:Number = (cur - prevs[i]);
				subject[propNames[i]] += add;
				remains[i] += (-add * direction);
				prevs[i] = cur;
			}
		}
		
		//common
		private function getValueEased(i:int):Number
		{
			return eased[i][passedRelative];
		}
		private function getValueLive(i:int):Number
		{
			return easing(passedRelative, propStartValues[i], propDifferences[i], duration);
		}
		
		private function passedDuration():void
		{
			equalize();
			if(onUpdate is Function) onUpdate.apply(null, onUpdateArgs);
			passedTotal = 0;
			resolveContinuation();
		}
		
		private function equalize():void
		{
			//# U.log('[AO][equalize]' + subject ,'|cycle:'+ +cycles+'|direction:'+ direction);
			if(!incremental) 
				if(direction > 0) 
					applyValues(propEndValues); 	// | > > > > > > [HERE]|
				else				
					applyValues(propStartValues);	// |[HERE] < < < < < < |
			else 		
				applyRemainings();
		}
		/** this is for incrementals only **/
		private function applyRemainings():void
		{
			for(var i:int=0;i<numProperties;i++)
			{
				subject[propNames[i]] += remains[i] * direction;
				remains[i] = propDifferences[i];
			}
			if(!yoyo || (yoyo && direction < 0))
				for(i=0; i < numProperties; i++)
					prevs[i] = propStartValues[i];
			else
				for(i=0; i < numProperties; i++)
					prevs[i] = propEndValues[i];
		}
		/** this is for absolutes only **/
		private function applyValues(v:Vector.<Number>):void
		{
			for(var i:int=0;i<numProperties;i++)
				subject[propNames[i]] = v[i];
		}
		
		private function resolveContinuation():void
		{
			//# U.log("------resolveContinuation----------");
			if(yoyo)
			{
				if(direction > 0)
					direction = -1;
				else
				{
					direction = 1;
					completeYoyo();
					cycled();
				}
			} 
			else cycled();
		}
		
		private function completeYoyo():void
		{
			if(onYoyoHalf is Function)
				onYoyoHalf.apply(null, onYoyoHalfArgs);
		}
		
		private function cycled():void
		{
			--cycles;
			if(onCycle is Function) 
				onCycle.apply(null, onCycleArgs);
			if(cycles == 0)
				finish(true);
		}
		
		//-------------------- controll ------------------//
		private function finish(dispatchComplete:Boolean):void { 
			//# U.log('[Easing][finish]',subject);
			if(destroyOnComplete)
				destroy(dispatchComplete);
			else
			{
				pause();
				if(onComplete != null)
					onComplete.apply(null, onCompleteArgs);
			}
		}
		
		private function gotoEnd():void
		{
			//# U.log('[Easing][gotoEND]',subject);
			equalize();
			if(yoyo && (direction > 0))
			{
				direction = -1;
				equalize();
			}
			direction = 1;
			passedTotal = 0;
		}
		
		private function gotoStart():void
		{
			//# U.log('[Easing][gotoSTART]',subject);
			equalize();
			if(direction > 0)
			{
				direction = -1;
				equalize();
			}
			direction = 1;
			passedTotal = 0;
		}
		
		private function removeFromPool():void
		{
			var i:int = animObjects.indexOf(this);
			if(i>-1) 
			{
				animObjects.splice(i,1);
				numObjects--;
				isPlaying = false;
			}
		}
		
		// ---------------------------------- public instance API------------------------------------------ //
		public function get isAnimating():Boolean { return isPlaying }
		public function start():void
		{
			//# U.log('[AO][Start]'+ subject);
			if(!isPlaying)
			{
				AO.animObjects[numObjects++] = this;
				isPlaying = true;
				if(onStart is Function) onStart.apply(null, onStartArgs);
				if(!isSetup)
					setUp();
			}
		}
		public function resume():void { start() };
		public function pause():void { removeFromPool() };
		/** @param goToDirection: negative - start position, 0 - stays still, positive - end position */
		public function stop(goToDirection:int=0, readNchanges:Boolean=false):void
		{
			//# U.log('[AO][Stop]'+subject);
			removeFromPool();
			if(goToDirection > 0) gotoEnd();
			else if(goToDirection < 0) gotoStart();
			isSetup = !readNchanges;
		}
		public function restart(goToDirection:int,readNchanges:Boolean=false):void
		{
			stop(goToDirection,readNchanges);
			start();
		}
		public function finishEarly(completeImmediately:Boolean):void
		{
			//# U.log('[Easing][finishEarly]',completeImmediately);
			if(completeImmediately)
			{
				gotoEnd();
				finish(true);
			}
			else finish(false);
		}
		
		// changes that require stop and re-read;
		public function get nIncremental():Boolean { return incremental }
		public function set nIncremental(v:Boolean):void { uIncremental = v }
		
		public function get nFrameBased():Boolean { return frameBased }
		public function set nFrameBased(v:Boolean):void { uFrameBased = v }
		
		public function get nPrecalculateFrameValues():Boolean { return precalculateFrameValues }
		public function set nPrecalculateFrameValues(v:Boolean):void {  uPrecalculateFrameValues = v }
		
		public function get nProperties():Object { return props }
		public function set nProperties(v:Object):void { uProps = v }
		
		public function get nSeconds():Number { return uSeconds }
		public function set nSeconds(v:Number):void { uSeconds = v }
		
		public function get nEasing():Function { return easing }
		public function set nEasing(v:Function):void { uEasing = v }
		
		// -----------------------  PUBLIC STATIC ------------------- //
		public static function get easing():Easings { return easings };
		public static function killOff(target:Object, completeImmediately:Boolean=false):void
		{
			//# U.log('[Easing][killOff]', target);
			var i:int = numObjects;
			if(target is AO)
				for(i= 0; i < numObjects;i++)
					if(animObjects[i] == target)
						animObjects[i--].finishEarly(completeImmediately);
			if(!(target is AO))
				for(i = 0; i < numObjects;i++)
					if(animObjects[i].subject === target)
						animObjects[i--].finishEarly(completeImmediately);
		}
		
		public static function contains(target:Object):Boolean
		{
			var i:int = numObjects;
			if(target is AO)
				while(i-->0)
					if(animObjects[i] == target)
						return true;
			if(!(target is AO))
				while(i-->0)
					if(animObjects[i].subject === target)
						return true;
			return false;
		}
		
		public static function broadcastFrame(frameTime:int):void
		{
			for(var i:int = 0; i < numObjects;i++)
				animObjects[i].tick(frameTime);
		}
		
		public static function set stage(v:Stage):void
		{
			if(STG != null) 
				STG.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
			STG = v;
			if(STG != null) 
				STG.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
		
		protected static function onEnterFrame(event:Event):void
		{
			curFrame = getTimer();
			frameTime = curFrame - prevFrame;
			prevFrame = curFrame;
			broadcastFrame(frameTime);
		}
		
		public static function animate(subject:Object, seconds:Number, props:Object, onComplete:Function=null, cycles:int=1,yoyo:Boolean=false,
											   easingType:Function=null, incremental:Boolean=false,frameBased:Boolean=true):AO
		{
			if(STG == null)
				throw new Error("[AO]Stage not set");
			var ao:AO = new AO(subject, seconds, props);
			ao.onComplete = onComplete || ao.onComplete;
			ao.cycles = cycles;
			ao.yoyo = yoyo;
			ao.nEasing = easingType;
			ao.nIncremental = incremental;
			ao.nFrameBased = frameBased;
			ao.start();
			return ao;
		}
	}
}