/**
 *
 * AXL Library
 * Copyright 2014-2015 Denis Aleksandrowicz. All Rights Reserved.
 *
 * This program is free software. You can redistribute and/or modify it
 * in accordance with the terms of the accompanying license agreement.
 *
 */
package axl.utils.binAgent
{
	import flash.display.DisplayObject;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.events.SyncEvent;
	import flash.events.UncaughtErrorEvent;
	import flash.geom.Rectangle;
	import flash.system.ApplicationDomain;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.ui.Keyboard;
	import flash.utils.describeType;
	
	import axl.ui.controllers.BoundBox;
	import axl.utils.AO;
	import axl.utils.U;
	
	public class Console extends Sprite
	{
		
		//window
		private var console_textFormat:TextFormat = new TextFormat('Lucida Console', 12, 0xaaaaaa);
		private var input_textFormat:TextFormat =  new TextFormat('Lucida Console', 12, 0x333333);
		private var consoleOutput_TextFormat:TextFormat =  new TextFormat('Lucida Console', 12, 0xFFDE9D);
		private var bConsole:TextField;
		private var bInput:TextField;
		private var bSlider:Sprite;
		private var bSliderRail:Sprite;
		private var past:Vector.<String> = new Vector.<String>();
		private var pastIndex:int;
		
		// internall
		private static var _instance:Console;
		private var stg:Stage;
		private var rootObj:DisplayObject;
		private var _pool:Object = {};
		
		// public api vars
		private var bIsEnabled:Boolean= true;
		private var bIsOpen:Boolean = false;
		private var bAllowGestureOpen:Boolean=true;
		private var bAllowKeyboardOpen:Boolean=true;
		private var bExternalTrace:Function;
		public var regularTraceToo:Boolean = true;
		
		//gesture opening
		private var nonKarea:Rectangle= new Rectangle(60,0,100,60);
		private var gestureRepetitions:int = 0;
		private var nonRepsIndicator:int = 4;
		private var boundBox:BoundBox;
		protected var totalString:String='';
		public var maxChars:uint = 80000;
		private var resizeListenerAdded:Boolean;
		
		public var passNewTextFunction:Function;
		public function Console(rootObject:DisplayObject)
		{
			if(instance != null)
			{
				bConsole = instance.bConsole;
				bInput = instance.bInput;
				bSlider = instance.bSlider;
				past = instance.past;
				pastIndex = instance.pastIndex;
				stg = instance.stg;
				rootObj = instance.rootObj;
				bIsEnabled = instance.bIsEnabled;
				bIsOpen = instance.bIsOpen;
				bAllowGestureOpen = instance.bAllowGestureOpen;
				bAllowKeyboardOpen = instance.bAllowKeyboardOpen;
				bExternalTrace = instance.bExternalTrace;
				regularTraceToo = instance.regularTraceToo;
				nonKarea = instance.nonKarea;
				nonRepsIndicator = instance.nonRepsIndicator;
				passNewTextFunction = instance.passNewText;
			}
			else
			{
				super();
				_instance = this;
				passNewTextFunction  = passNewText;
				rootObj = rootObject;
				build();
				rootSetup();
				trrace("==== BIN AGENT 0.0.11 ====");
			}
		}
		
		public static function get instance():Console { return _instance }
		
		private function build():void
		{
			build_console();
			build_consoleSlider();
			build_input();
			align();
		}
		
		private function buildControler():void
		{
			boundBox = new BoundBox();
			boundBox.horizontal = false;
			boundBox.vertical = true;
			boundBox.verticalBehavior  = BoundBox.inscribed;
			boundBox.bound = bSliderRail;
			boundBox.box = bSlider;
			boundBox.addEventListener(Event.CHANGE, sliderEvent);
		}
		
		private function build_console():void
		{
			bConsole = new TextField();
			bConsole.defaultTextFormat = console_textFormat;
			bConsole.multiline = true;
			bConsole.wordWrap= true;
			bConsole.border = true;
			bConsole.width = 500;
			bConsole.height = 200;
			bConsole.background = true;
			bConsole.backgroundColor = 0x212121;
			bConsole.type = 'dynamic';
			bConsole.selectable = true;
			bConsole.addEventListener(Event.SCROLL, scrollEvent);
			this.addChild(bConsole);
		}
		
		private function build_input():void
		{
			bInput = new TextField();
			bInput.defaultTextFormat = input_textFormat;
			bInput.multiline = false;
			bInput.wordWrap= true;
			bInput.border = true;
			bInput.width = 500;
			bInput.height = 17;
			bInput.background=true;
			bInput.backgroundColor= 0xffffff;
			bInput.type = 'input';
			bInput.addEventListener(KeyboardEvent.KEY_UP, KEY_UP);
			this.addChild(bInput);
		}
		
		private function build_consoleSlider():void
		{
			bSliderRail = new Sprite();
			bSliderRail.graphics.beginFill(0xffffff,0.3);
			bSliderRail.graphics.drawRect(0,0,15,console.height);
			bSliderRail.graphics.endFill();
			bSliderRail.mouseChildren = false;
			this.addChild(bSliderRail);
			bSlider = new Sprite();
			bSlider.graphics.beginFill(0xffffff);
			bSlider.graphics.drawRoundRect(0,0, 15,25,5,5);
			bSlider.graphics.endFill();
			bSlider.mouseChildren = false;
			this.addChild(bSlider);
		}
		
		protected function align():void
		{
			bSlider.x = bConsole.x + bConsole.width - bSlider.width;
			bSlider.y = bConsole.y + bConsole.height - bSlider.height;
			bSliderRail.x = bSlider.x
			bInput.y = bConsole.height;
		}
		
		//-------
		//-------------------------------------  ROOT SETUP ------------------------------------------  //
		
		private function rootSetup():void
		{
			rootObj.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, uncaughtError);
			this.addEventListener(Event.ADDED_TO_STAGE, ats);
			this.addEventListener(Event.REMOVED_FROM_STAGE, rfs);
			if(rootObj.stage != null)
				giveStage(rootObj.stage);
			else
				rootObj.addEventListener(Event.ADDED_TO_STAGE, gotStage);
		}
		
		private function ats(e:Event):void 
		{
			refreshWindow();
			stg.focus= this.bInput;
			bIsOpen = true;
			if(!resizeListenerAdded)
			{
				stg.addEventListener(Event.RESIZE, stageResized);
				resizeListenerAdded = true;
			}
		}
		
		protected function stageResized(event:Event):void
		{
			if(this.stage)
				resize(stage.stageWidth, stage.stageHeight);
		}
		private function rfs(e:Event):void
		{
			bIsOpen = false;
		}
	
		private function gotStage(event:Event=null):void { giveStage(rootObj.stage) }
		private function giveStage(stage:Stage):void
		{
			axl.utils.U.log(this, "Stage given",stage);
			rootObj.removeEventListener(Event.ADDED_TO_STAGE, gotStage);
			if(stg != null) return;
			stg = stage;
			stg.loaderInfo.sharedEvents.dispatchEvent(new SyncEvent('axl.utils.binAgent',true,false,[this]));
			if(stg)
			{
				stg.loaderInfo.sharedEvents.addEventListener('axl.utils.binAgent', onBibAgentSyncEvent);
				AO.stage = stage;
				buildControler();
				stg.addEventListener(MouseEvent.MOUSE_UP, mu);
				allowKeyboardOpen = allowKeyboardOpen;
				allowGestureOpen = allowGestureOpen;
				align();
			}
		}
		
		protected function onBibAgentSyncEvent(e:SyncEvent):void
		{
			trrace("BIN AGENT NEW INSTANCE ATTEMPT ",e.changeList);
			if(e.changeList && e.changeList.length > 0)
			{
				var b:Object = e.changeList[0];
				b.transferInstance(this);
			}
			else
			{
				trrace("TRANSFERING BIN AGENT INSTANCE FAILED (changesList)", e.changeList,e.changeList.length > 0)
			}
		}
		
		protected function transferInstance(parentConsole:Object):void
		{
			trrace('transferInstance');
			if(parentConsole && parentConsole.hasOwnProperty('passNewText'))
			{
				passNewTextFunction = parentConsole.passNewText;
				passNewTextFunction('[MERGE CONSOLE INSTANCES]' + totalString + '[/MERGE CONSOLE INSTANCES]');
				destroy();
			}
			else
			{
				trrace("TRANSFERING BIN AGENT INSTANCE FAILED (instance)", parentConsole, parentConsole.hasOwnProperty('passNewText'));
			}
			
		}
		
		private function uncaughtError(e:UncaughtErrorEvent):void
		{
			var message:String;
			if (e.error is Error)
				message = Error(e.error).message;
			else if (e.error is ErrorEvent)
				message = ErrorEvent(e.error).text;
			else
				message = e.error.toString();
			trrace('[BinAgent][UNHANDLED-ERROR] uncaught error: ', message, '(', e.error, e.text, e.toString(), e.type, e.target, ')');
			var et:Error = e.error as Error;
			if(et)
				trrace(et.getStackTrace());
			e.preventDefault();
		}
		//-------------------------------------  END OF ROOT SETUP  ------------------------------------------  //
		//-------
		// ------------------------------------- WINDOW CONTROLL ------------------------------------- //
		
		protected function sliderEvent(event:Event):void
		{
			boundBox.changeNotifications=false;
			boundBox.liveChanges=false;
			bConsole.removeEventListener(Event.SCROLL, scrollEvent);
			bConsole.scrollV = this.boundBox.percentageVertical * bConsole.maxScrollV;
			bConsole.addEventListener(Event.SCROLL, scrollEvent);
			boundBox.changeNotifications=true;
			boundBox.liveChanges=true;
		}
		
		protected function scrollEvent(e:Event):void
		{
			if(boundBox)
			{
				var n:Number = bConsole.scrollV /  bConsole.maxScrollV;
				var dif:Number = Math.abs(n - boundBox.percentageVertical);
				if(dif > 0.01)
				{
					boundBox.changeNotifications=false;
					boundBox.liveChanges=false;
					bConsole.removeEventListener(Event.SCROLL, scrollEvent);
					boundBox.percentageVertical = n;
					bConsole.addEventListener(Event.SCROLL, scrollEvent);
					boundBox.changeNotifications=true;
					boundBox.liveChanges=true;
				}
			}
		}
		protected function stageMouseDown(e:MouseEvent):void
		{
			if((e.stageY > nonKarea.height) || (e.stageX  > nonKarea.x))
				gestureRepetitions = 0;
		}
		
		private function localMouseDown(e:MouseEvent):void
		{
			// some software may still focus e.g. Feathers
			if(e.target == bInput && stg.focus != bInput)
				stg.focus = bInput;
			if(e.shiftKey)
				this.startDrag();
			//sliderIsDown = (e.target == bSlider);
		}
		
		private function mu(e:MouseEvent):void
		{
			if(stg != null)
			{
				this.stopDrag()
				//sliderIsDown = false;
			}
			if(allowGestureOpen)
			{
				if((e.stageY > nonKarea.height) || (e.stageX < (nonKarea.x + nonKarea.width)))
					gestureRepetitions = 0;
				else if(++gestureRepetitions > nonRepsIndicator-1)
					openClose();
			}
		}
		
		protected function stageKeyDown(e:KeyboardEvent):void
		{
			if(e.altKey && e.ctrlKey && (e.keyCode == Keyboard.RIGHT)) // alt + s
				openClose();
		}
		
		// uses parent a bin may be addaed anywhere..
		private function openClose():void
		{
			if(bIsOpen)
				this.parent.removeChild(this);
			else if(stg != null)
			{
				align();
				stg.addChild(this);
				stg.focus =bInput;
			}
			gestureRepetitions = 0;
		}
		//----
		protected function KEY_UP(e:KeyboardEvent):void
		{
			switch (e.keyCode)
			{
				case Keyboard.ENTER: enterConsoleText();
					break;
				case Keyboard.UP:
				case Keyboard.DOWN: showPast(e.keyCode);
					break;
			}
		}
		
		protected function showPast(kc:int):void
		{
			if(past.length < 1) return;
			pastIndex += (kc == Keyboard.UP ? 1 : -1);
			if(pastIndex < 0) 
				pastIndex = past.length-1;
			if((pastIndex >= past.length) || (pastIndex < 0))
				pastIndex = 0;
			bInput.text = past[pastIndex];	
			bInput.setSelection(0, bInput.text.length);
		}
		
		protected function enterConsoleText():void
		{
			var t:String = bInput.text;
			if(t.length < 1)
				return;
			var tstart:int = bConsole.text.length;
			var tlen:int = trrace(t);
			if(tstart < bConsole.text.length)
			{
				bConsole.setTextFormat(consoleOutput_TextFormat, tstart, tstart +tlen);
			}
			bConsole.scrollV = bConsole.maxScrollV;
			
			try{ trrace(PARSE_INPUT(t))}
			catch (e:*) { trrace("[BinAgent]ERROR OCCURED:\n", e) }
			if((tstart + tlen) < bConsole.text.length)
				bConsole.setTextFormat(console_textFormat, tstart +tlen);
			if(past.indexOf(t) < 0)
				past.unshift(t);
			else
				past.unshift(past.splice(past.indexOf(t),1).pop());
			pastIndex=-1;

			bInput.text = '';
		}
		
		//------
		public function trrace(...args):int
		{
			if(!bIsEnabled) return 0;
			if(regularTraceToo)
				trace.apply(null,args);
			var v:Object;
			var s:String='';
			for(var i:int = 0; i < args.length; i++)
			{
				v = args[i];
				if(v == null)
					s += 'null';
				else if(v is String)
					s += v;
				else if(v is XML || v is XMLList)
					s += v.toXMLString();
				else
					s += v.toString();
				if(args.length - i > 1)
					s += ' ';
			}
			s += '\n';
			passNewTextFunction(s);
			v=null;
			return s.length;
		}
		
		public function passNewText(s:String):void
		{
			totalString += s;
			var numChars:int = totalString.length;
			if(maxChars > 0 && numChars > maxChars)
				totalString = totalString.substr(numChars - maxChars);
			if(this.stg != null)
				refreshWindow();
			if(bExternalTrace != null)
				bExternalTrace(s);
		}
		
		private function refreshWindow():void
		{
			bConsole.text = totalString;
			bConsole.scrollV = bConsole.maxScrollV;
			if(boundBox != null && boundBox.percentageVertical != 1)
				boundBox.percentageVertical = 1;
			if(this.parent)
				this.parent.setChildIndex(this, this.parent.numChildren-1);
		}
		
		//-------------------------------------  	    PUBLIC API  ------------------------------------------  //
		/** Opens and closes bin window programatically */
		public function get isOpen():Boolean { return bIsOpen }
		public function set isOpen(v:Boolean):void
		{
			if(v == bIsOpen || stg == null) return;
			if(v) stg.addChild(this);
			else if(this.parent != null) this.parent.removeChild(this)
		}
		/** controlls non-programatic opening of the bin window. @see BinAgent */
		public function get allowGestureOpen():Boolean { return bAllowGestureOpen }
		public function set allowGestureOpen(v:Boolean):void
		{
			bAllowGestureOpen = v;
			if(stg != null)
			{
				stg.removeEventListener(MouseEvent.MOUSE_DOWN, stageMouseDown); 
				if(bAllowGestureOpen)
					stg.addEventListener(MouseEvent.MOUSE_DOWN, stageMouseDown); 
			}
		}
		
		/** controlls non-programatic opening of the bin window. @see BinAgent */
		public function get allowKeyboardOpen():Boolean { return bAllowKeyboardOpen }
		public function set allowKeyboardOpen(v:Boolean):void
		{
			bAllowKeyboardOpen = v;
			if(stg != null)
			{
				stg.removeEventListener(KeyboardEvent.KEY_DOWN, stageKeyDown);
				if(bAllowKeyboardOpen)
					stg.addEventListener(KeyboardEvent.KEY_DOWN, stageKeyDown);
			}
		}
		
		public function get console():TextField { return bConsole }
		public function get input():TextField { return bInput}
		public function get slider():Sprite { return bSlider }
		
		/** enables or disables all trace (external and internal */
		public function get isEnabled():Boolean { return bIsEnabled }
		public function set isEnabled(value:Boolean):void { bIsEnabled = value }
		/**allows to route your trace to any external output like Externalnterface.call 
		 * Function should accept only one argument of type <code>String</code>*/
		public function get externalTrace():Function { return bExternalTrace }
		public function set externalTrace(value:Function):void { bExternalTrace = value }
		/** clears entire console text */
		public function clear():void { console.text = totalString = '' };
		/** resizes it to specified dimensions, 0 means parameter untouched */
		public function resize(w:Number, h:Number=0):void
		{
			if(w != 0)
			{
				console.width = w;
				input.width = w;
			}
			if(h !=0)
			{
				console.height = h - input.height;
				bSliderRail.graphics.clear();
				bSliderRail.graphics.beginFill(0xffffff,0.3);
				bSliderRail.graphics.drawRect(0,0,15,console.height);
				bSliderRail.graphics.endFill();
				bSliderRail.mouseChildren = false;
			}
			align();
		}
		
		/** Lists classes available in current ApplicationDomain. Does not include flash sdk classes*/
		public function get listClasses():String { 
			return structureToString(ApplicationDomain.currentDomain['getQualifiedDefinitionNames']())
		}
		/** Reads structure of nested arrays vectors and objects and returns it as a well formated string*/
		public function structureToString(input:Object, deep:String=''):String
		{
			var output:String='', t:String = '  ';
			if(input == null) return 'null\n';
			output +=  input.toString() + '\n';
			for(var p:String in input)
				output +=  deep + t + p +' : ' + structureToString(input[p], deep + t);
			return output;
		}
		
		/** Returns well formated string (tree structure) of parent node's children structure
		 * @param parentNode - any display object (flash,starling). Default - flash stage.
		 * @param properties - array of properties that will be checked for each particular 
		 * display list element, e.g, ['x','y','width','height'] */
		public function displayList(parentNode:Object=null,properties:Array=null):String
		{
			var ncp:String = 'numChildren', gcap:String = 'getChildAt', t:String='  ', n:String='\n';
			if(parentNode == null) parentNode = stg;
			if(properties == null) properties = [];
			var np:int = properties.length;
			var output:String = recurse(parentNode, properties);
			function recurse(o:Object, p:Array, d:String=''):String
			{
				var s:String=(d+o.toString());
				var nc:int = o.hasOwnProperty(ncp) ?  o[ncp] : 0;
				for(var i:int = 0; i < np; i++)
					s += '|'+(o.hasOwnProperty(p[i]) ?  o[p[i]] : ("?" +p[i] +"?").toString());
				for(i=0;i<nc;i++)
					s += String(n+t+recurse(o[gcap](i),p,d+t));
				return s;
			}
			return output;
		}
		
		/** executes flash.utils.describeType on object */
		public function desc(a:Object=null):void { trrace(flash.utils.describeType(a)) }
		/** your pool. allows to asign elements to test quickly. */
		public function get pool():Object { return _pool }
		
		//--- magic
		protected function PARSE_INPUT(s:String):Object
		{
			// allows to keep console only
			// BinAgent which only extends this class overrides this one
			return s;
		}
		
		private function destroy():void
		{
			this.removeChildren();
			console_textFormat = null;
			input_textFormat = null;
		
			if(boundBox)
			{
				boundBox.removeEventListener(Event.CHANGE, sliderEvent);
				boundBox.destroy();
			}
			boundBox = null;
			if(bConsole)
			{
				bConsole.addEventListener(Event.SCROLL, scrollEvent);
			}
			bConsole = null;
			if(bInput)
				bInput.addEventListener(KeyboardEvent.KEY_UP, KEY_UP);
			bInput = null;
			if(rootObj)
				rootObj.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, uncaughtError);
			if(rootObj)
				rootObj.removeEventListener(Event.ADDED_TO_STAGE, gotStage);
			this.removeEventListener(Event.ADDED_TO_STAGE, ats);
			this.removeEventListener(Event.REMOVED_FROM_STAGE, rfs);
			if(stg)
			{
				stg.removeEventListener(Event.RESIZE, stageResized);
				stg.removeEventListener(MouseEvent.MOUSE_UP, mu);
				stg.loaderInfo.sharedEvents.removeEventListener('axl.utils.binAgent', onBibAgentSyncEvent);
				stg.removeEventListener(MouseEvent.MOUSE_DOWN, stageMouseDown); 
				stg.removeEventListener(KeyboardEvent.KEY_DOWN, stageKeyDown);
				stg = null;
			}
			if(bSlider)
				bSlider.graphics.clear();
			bSlider = null;
			if(bSliderRail)
				bSliderRail.graphics.clear();
			bSliderRail = null;
			if(past)
				past.length = 0;
			past = null;
			
			rootObj = null;
			_pool = null;
			bIsOpen = false;
			allowKeyboardOpen = false;
			allowGestureOpen = false;
			nonKarea = null;
			totalString = null;
		}
	}
}