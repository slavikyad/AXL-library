import flash.display.Loader;
import flash.display.LoaderInfo;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.filesystem.File;
import flash.media.Sound;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.system.ApplicationDomain;
import flash.system.ImageDecodingPolicy;
import flash.system.LoaderContext;
import flash.utils.ByteArray;
import flash.utils.describeType;
import flash.utils.getDefinitionByName;

import axl.utils.Ldr;

/**
 * This class represents each <b> queue </b> (not a single asset)
 */
internal class Req extends EventDispatcher {
	
	public static const fileInterfaceAvailable:Boolean =  ApplicationDomain.currentDomain.hasDefinition('flash.filesystem::File');
	public static const FileClass:Class = fileInterfaceAvailable ? getDefinitionByName('flash.filesystem::File') as Class : null;
	public static const FileStreamClass:Class = fileInterfaceAvailable ? getDefinitionByName('flash.filesystem::FileStream') as Class : null;
	private static const networkRegexp:RegExp = /^(http:|https:|ftp:|ftps:)/i;
	
	private static function log(...args):void { if(verbose is Function) verbose.apply(null,args) }
	public static var verbose:Function;
	
	public static var loaders:Object;
	public static var urlLoaders:Object;
	public static var objects:Object;
	
	public static var networkOverPrefixes:Boolean = true;
	private static var _numAllRemaining:int=0; // ++ every item added, -- every item loaded and/or skipped. 0 on all queues done
	private static var _numAllQueued:int=0; //  ++ every item queued. 0 on all queues done
	private static var _numAllLoaded:int=0; // ++ every item loaded, -- every item successfully loaded. 0 on all queues done
	private static var _numAllSkipped:int=0; // ++ every item load hard fail, 0 on all queues done
	private var numCurrentRemaining:int =0; // as above but appplying to current queue
	private var numCurrentQueued:int=0; // as above but appplying to current queue
	private var numCurrentLoaded:int=0; // as above but appplying to current queue
	private var numCurrentSkipped:int=0; // as above but appplying to current queue
	
	public static function allQueuesDone():void { _numAllQueued = _numAllRemaining = _numAllLoaded = _numAllSkipped = 0}
	public static function get numAllRemaining():int { return _numAllRemaining}
	public static function get numAllQueued():int { return _numAllQueued }
	public static function get numAllLoaded():int { return _numAllLoaded }
	public static function get numAllSkipped():int { return _numAllSkipped }
	
	public function currentQueueDone():void { numCurrentQueued = numCurrentLoaded = numCurrentRemaining= numCurrentSkipped = 0}
	public function get numLoaded():int { return numCurrentLoaded }
	public function get numRemaining():int { return numCurrentRemaining }
	public function get numQueued():int { return numCurrentQueued }
	public function get numSkipped():int { return numCurrentSkipped }

	private var prefixList:Vector.<String> = new Vector.<String>();
	private var prefix:String;
	private var prefixIndex:int=0;
	private var numPrefixes:int;
	
	private var pathList:Vector.<String> = new Vector.<String>();
	private var originalPath:String;
	private var concatenatedPath:String;
	private var subpath:String;
	private var filename:String;
	private var extension:String;
	
	public var storingBehaviour:Object
	private var storePrefix:String;
	
	private var listeners:Array;
	
	public var urlRequest:URLRequest;
	public var urlLoader:URLLoader;
	public var loaderInfo:LoaderInfo;
	
	public var onComplete:Function;
	public var individualComplete:Function;
	public var onProgress:Function;
	
	public var isLoading:Boolean;
	public var isDone:Boolean;
	
	private var eventComplete:Event = new Event(Event.COMPLETE);
	
	public function Req()
	{
		
	}
	
	public function addPaths(v:Object):int
	{
		var flatList:Vector.<String> = new Vector.<String>();
			flatList = getFlatList(v, flatList);
		var i:int, j:int, l:int = pathList.length;
		counters(-l);
		for(i=0,j= flatList.length; i<j; i++)
			if(pathList.indexOf(flatList[i]) < 0)
				pathList[l++] = flatList[i];
		flatList.length = 0;
		flatList = null;
		counters(l);
		log("[Ldr][Queue] added to queue. state:", Ldr.state);
		return l;
	}
	
	public function removePaths(v:Object):int
	{
		var flatList:Vector.<String> = new Vector.<String>();
		flatList = getFlatList(v, flatList);
		var i:int, k:int, l:int = pathList.length;
		counters(-l);
		for(i= flatList.length; i-->0;) {
			k = pathList.indexOf(flatList[i]);
			if(k>-1)
				pathList.splice(k,1);
		}
		flatList.length = 0;
		flatList = null;
		l = pathList.length;
		counters(l);
		log("[Ldr][Queue] removed from queue. state: ' ", Ldr.state);
		return l;
	}
	
	private function counters(v:int):void
	{
		numCurrentRemaining +=v;
		numCurrentQueued += v;
		_numAllRemaining += v;
		_numAllQueued += v;
	}
	
	public function addPrefixes(v:Object):int
	{
		var flatList:Vector.<String> = new Vector.<String>();
		flatList = getFlatList(v, flatList,false);
		var i:int, j:int, k:int, l:int = prefixList.length;
		for(i=0,j= flatList.length; i<j; i++)
			if(prefixList.indexOf(flatList[i]) < 0)
				prefixList[l++] = flatList[i];
		flatList.length = 0;
		flatList = null;
		numPrefixes = prefixList.length;
		return numPrefixes;
	}
	
	public function set storeDirectory(v:Object):void
	{
		if(!fileInterfaceAvailable) storePrefix = null;
		if(v is String){
			try { 
				var f:Object = new FileClass(v);
				storePrefix = f.isDirectory ? f.nativePath : null;
			}
			catch(e:ArgumentError) { storePrefix = null }
			f = null;
		}
		else if(v is FileClass && v.isDirectory) storePrefix = v.nativePath;
		else storePrefix = null;
	}
	
	private function getFlatList(v:Object, ar:Vector.<String>,filesLookUp:Boolean=true):Vector.<String>
	{
		var i:int = ar.length;
		if(v is String) ar[i] = v;
		else if (fileInterfaceAvailable && v is FileClass)//ar[i] = v.nativePath;
		{
			if(filesLookUp) processFilesRecurse(v, ar); // paths
			else if(v.isDirectory) ar[i] = v.nativePath; // prefixes 
		}
		else if (v is XML || v is XMLList) processXml(XML(v), ar);
		else if(v is Array || v is Vector.<FileClass> || v is Vector.<String> || v is Vector.<XML> || v is Vector.<XMLList>)
			for(var j:int = 0, k:int = v.length;  j < k; j++)
				ar = ar.concat(getFlatList(v[j], new Vector.<String>()));
		return ar;
	}
	
	private function processFilesRecurse(f:Object, flat:Vector.<String>):void
	{
		if(f.isDirectory)
		{
			var v:Array = f.getDirectoryListing();
			while(v.length)
				processFilesRecurse(v.pop(),flat);
			v = null;
		} else { flat.push(f.nativePath) }
		f = null;
	}
	
	private function processXml(node:XML, flat:Vector.<String>, addition:String=''):void
	{
		var nodefiles:XMLList = node.files;
		var subAddition:String = addition +  String(nodefiles.@dir)
		for( var i:int = 0, j:int = nodefiles.length(); i<j; i++)
			processXml(XML(nodefiles[i]), flat, subAddition);
		nodefiles = node.file;
		for(i = 0, j = nodefiles.length(); i<j; i++)
			flat.push(addition + nodefiles[i].toString());
	}
	
	
	private function get validatedPrefix():String
	{
		if(prefixList.length < 1)
		{
			prefixList[0] = '';
			numPrefixes = prefixList.length;
		}
		if(prefixIndex < numPrefixes) return prefixList[prefixIndex];
		else return null;
	}
	
	private function getSubpathDetails():void
	{
		originalPath = subpath.substr();
		var i:int = originalPath.lastIndexOf("/") +1;
		var j:int = originalPath.lastIndexOf("\\")+1;
		var k:int = originalPath.lastIndexOf(".") +1;
		
		extension	= originalPath.substr(k);
		filename 	= originalPath.substr(i>j?i:j);
	}
	
	private function getConcatenatedPath(prefix:String, originalUrl:String):String
	{
		if(prefix.length < 1) return originalUrl;
		if(networkOverPrefixes && originalUrl.match(networkRegexp))
		{
			prefixIndex =numPrefixes;
			return originalUrl;
		}
		if(fileInterfaceAvailable && prefix.match(/^(\.\.)/i))
		{ trace('--');
			// workaround for inconsistency in traversing up directories. 
			// FP takes working dir, AIR doesn't. There are also isssues with
			// FileClass.applicationDirectory.resolvePath(..).nativePath - still points to the same dir
			// FileClass.applicationDirectory.nativePath + '/' + prefix; - Sandbox violation
			// workaround for inconsistency of traversing up directories. FP takes working dir, AIR doesn't
			var cp:String = FileClass.applicationDirectory.nativePath + FileClass.separator + prefix; 
			try {
				var f:Object = new FileClass(cp) ;
				return  f.resolvePath(f.nativePath + originalUrl).nativePath;
			} catch (e:*) { log('[Ldr][Queue] can not resolve path:',prefix + originalUrl, e, 'trying as URLloader')
			} finally { f = null }
		}
		//fixes concat two styles an doubles. all go to "/" since this is default url style, ios supports that, windows can resolve
		var joint:String = prefix.substr(-1) + originalUrl.charAt(0);
		if(joint == '//' || joint == '\\')
			prefix = prefix.substr(0,-1);
		else if (!joint.match(/(\\|\/)/))
			prefix += '/';
		return String(prefix + originalUrl).replace(/\\/gi, "/");
	}
	
	public function stop():void { pathList = null }
	
	public function load():void
	{
		log("[Ldr][Queue] start");
		isLoading = true;
		nextElement();
	}
	
	private function finalize():void
	{
		this.dispatchEvent(eventComplete);
		isLoading = false;
		isDone = true;
	}
	
	private function nextElement():Boolean
	{
		// validate end of queue
		numCurrentRemaining = pathList.length;
		if(numCurrentRemaining < 1)
			return finalize();
		if(!isLoading) // can be paused
			return false
		
		prefix = validatedPrefix;
		subpath = pathList.pop();
		
		//subpath should throw an error or log message at least though
		if(!(prefix is String) || !(subpath is String))
			return nextElement();
		
		// get initial details. originalPath is nulled out in onBothloadersComplete
		if(!originalPath)
			getSubpathDetails();		
		
		//validate already existing elements - this should be up to user if he wants to unload current contents !
		if(objects[filename] || urlLoaders[filename] || loaders[filename])
		{
			log("[Ldr][Queue]["+filename+"] OBJECT ALREADY EXISTS!");//,'/',objects[filename],'/', urlLoaders[filename],'/', loaders[filename]);
			_numAllRemaining--;
			numCurrentRemaining--;
			if(individualComplete is Function)
				individualComplete(filename);
			return nextElement();
		}
		
		//merge prefix & subpath
		concatenatedPath = getConcatenatedPath(prefix, originalPath);
		
		//setup loaders and load
		urlLoader = new URLLoader();
		urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
		urlLoaders[filename] = urlLoader;
		
		listeners = [urlLoader, onError, onError, onHttpResponseStatus, onLoadProgress, onUrlLoaderComplete];
		addListeners.apply(null, listeners);
		urlRequest = new URLRequest(concatenatedPath);
		log("[Ldr][Queue]["+filename+"] loading:", urlRequest.url);
		urlLoader.load(urlRequest);
		// end of nextElement flow - waiting for eventDispatchers
		return true
	}
	
	private function onUrlLoaderComplete(e:Object):void
	{
		log("[Ldr][Queue]["+filename+"] instantiation..");
		var bytes:ByteArray = urlLoader.data as ByteArray;
		if(bytes)
			saveIfRequested(bytes);
		switch (extension.toLowerCase())
		{
			case "mpeg":
			case "mp3":
				bothLoadersComplete(instantiateSound(bytes));
				break;
			case "jpg":
			case "jpeg":
			case "png":
			case "gif":
				loaderInfo = instantiateImage(bytes, onError, onLoaderComplete);
				break;
			case 'xml':
				bothLoadersComplete(XML(bytes));
				break
			case 'json':
				bothLoadersComplete(JSON.parse(bytes.readUTFBytes(bytes.length)))
				break;
			default: // any other remains untouched, atf is here too
				bothLoadersComplete(bytes);
				break;
		}
	}
	
	private function bothLoadersComplete(asset:Object):Boolean
	{
		objects[filename] = asset;
		delete urlLoaders[filename];
		var url:String = urlRequest.url;
		if(urlLoader)
			removeListeners.apply(null, listeners);
		
		if(loaderInfo)
		{
			loaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onError);
			loaderInfo.removeEventListener(Event.COMPLETE, onLoaderComplete);
		}
		
		if((asset == null) && (++prefixIndex < numPrefixes))
		{
			pathList.push(originalPath);
			log("[Ldr][Queue]["+filename+"] soft fail:", url, 
				'\n[Ldr][Queue]['+filename+'] Trying alternative dir:', validatedPrefix);
		}
		else
		{
			if(asset != null)
			{
				log("[Ldr][Queue]["+filename+"] LOADED:", url);
				numCurrentLoaded++;
				_numAllLoaded++;
			}
			else
			{
				numCurrentSkipped++;
				_numAllSkipped++;
				log("[Ldr][Queue]["+filename+"] HARD FAIL:", url, "NO MORE ALTERNATIVES");
			}
			prefixIndex=0;
			originalPath = null;
			_numAllRemaining--;
			numCurrentRemaining--;
			if(individualComplete is Function)
				individualComplete(filename);
			log("[Ldr][Queue]["+filename+"] element completed. state:", Ldr.state);
		}
		return nextElement();
	}
	
	
	private function saveIfRequested(data:ByteArray):void
	{
		if((storePrefix != null) && fileInterfaceAvailable)
		{
			trace("STORE PREFIX IS", storePrefix, '[', storePrefix.length,']');
			var f:Object;
			var path:String = getConcatenatedPath(storePrefix, originalPath);
			log("[Ldr][Queue]["+filename+"][Save] saving:", path);
			//resolving file locating
			try{ f= new FileClass(path) } 
			catch (e:ArgumentError) { log("[Ldr][Queue]["+filename+"][Save] FAIL:",path,e) }
			
			//validation and filters
			f = storingFilter(f, urlRequest.url);
			if(f == null)
				return log("[Ldr][Queue]["+filename+"][Save] Storing criteria doesn't match, abort");
			
			//writing to disc
			var fr:Object = new FileStreamClass();
			try{ 
				fr.open(f, 'write'); // openAsync doesn't fire COMPLETE in write mode so can't stick to where remove async listeners  
				fr.writeBytes(data);
				fr.close();
				fr = null;
				log("[Ldr][Queue]["+filename+"][Save] SAVED:", f.nativePath, '[', data.length / 1024, 'kb]');
			} catch (e:Error) { log("[Ldr][Queue]["+filename+"][Save] FAIL: cant save as:",f.nativePath,'\n',e) }
			f = null;
		}
	}
	private function baseValidation(file:Object, url:String):Object
	{
		if(!(file is FileClass) || file.isDirectory){
			Ldr.log("[Ldr][Queue]["+filename+"][Save][criteria] file is not File");
			return null;
		}
		else if(file.url == url){
			Ldr.log("[Ldr][Queue]["+filename+"][Save][criteria] store and load directiries are equal");
			return null;
		}
		return file;
	}
	private function storingFilter(file:Object, url:String):Object
	{
		Ldr.log("[Ldr][Queue]["+filename+"][Save][criteria]", storingBehaviour, file, url);
		
		if(baseValidation(file, url) == null) return null
		if((storingBehaviour is Function) && (storingBehaviour.length == 2))
		{
			log("[Ldr][Queue]["+filename+"][Save][criteria] user function");
			return baseValidation(storingBehaviour.apply(null,[file, url]),url);
		}
		else if(storingBehaviour is RegExp) 
		{
			log("[Ldr][Queue]["+filename+"][Save][criteria] regexp match");
			return url.match(storingBehaviour) ? file : null;
		}
		else if(storingBehaviour is Date)
		{
			log("[Ldr][Queue]["+filename+"][Save][criteria] date comparison");
			if(!file.exists) return file;
			return (file.modificationDate.time < storingBehaviour.time) ? file : null
		}
		else if(storingBehaviour is Number)
		{
			log("[Ldr][Queue]["+filename+"][Save][criteria] number comparison");
			if(!file.exists) return file;
			return (file.modificationDate.time < storingBehaviour)
		}
		else {
			Ldr.log("[Ldr][Queue]["+filename+"][Save][criteria] unrecognized criteria\n", flash.utils.describeType(storingBehaviour));
			return null;
		}
	}
	
	// event handlers
	private function onHttpResponseStatus(e:HTTPStatusEvent):void
	{
		if (extension == null)
		{
			var headers:Array = e["responseHeaders"];
			var contentType:String = getHttpHeader(headers, "Content-Type");
			
			if (contentType && /(audio|image)\//.exec(contentType))
				extension = contentType.split("/").pop();
		}
	}
	
	private function onLoadProgress(e:ProgressEvent):void
	{
		if(e.bytesTotal > 0)
			onProgress(e.bytesLoaded / e.bytesTotal, filename);
	}
	
	private function onLoaderComplete(event:Object):void
	{
		urlLoader.data.clear();
		loaders[filename] = loaderInfo.loader;
		bothLoadersComplete(event.target.content);
	}
	
	private function onError(e:Event):void
	{
		bothLoadersComplete(null);
	}
	
	// helpers
	
	private static function instantiateImage(bytes:ByteArray, onIoError:Function, onLoaderComplete:Function):LoaderInfo
	{
		var loader:Loader = new Loader();
		
		var loaderInfo:LoaderInfo = loader.contentLoaderInfo;
		loaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onIoError);
		loaderInfo.addEventListener(Event.COMPLETE, onLoaderComplete);
		
		loader.loadBytes(bytes, context);
		return loaderInfo;
	}
	
	private static function instantiateSound(bytes:ByteArray):Sound
	{
		var sound:Sound = new Sound();
		sound.loadCompressedDataFromByteArray(bytes, bytes.length);
		bytes.clear();
		return sound;
	}
	
	private  function getHttpHeader(headers:Array, headerName:String):String
	{
		if (headers)
			for each (var header:Object in headers)
				if (header.name == headerName) return header.value;
		return null;
	}
	
	private function addListeners(urlLoader:URLLoader, onIoError:Function, onSecurityError:Function, 
										 onHttpResponseStatus:Function, onLoadProgress:Function, onUrlLoaderComplete:Function):void
	{
		urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onIoError);
		urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
		urlLoader.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHttpResponseStatus);
		urlLoader.addEventListener(Event.COMPLETE, onUrlLoaderComplete);
		if(onProgress is Function)
			urlLoader.addEventListener(ProgressEvent.PROGRESS, onLoadProgress);
	}
	private  function removeListeners(urlLoader:URLLoader, onIoError:Function, onSecurityError:Function, 
											onHttpResponseStatus:Function, onLoadProgress:Function, onUrlLoaderComplete:Function):void
	{
		urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onIoError);
		urlLoader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
		urlLoader.removeEventListener(HTTPStatusEvent.HTTP_STATUS, onHttpResponseStatus);
		urlLoader.removeEventListener(Event.COMPLETE, onUrlLoaderComplete);
		if(urlLoader.hasEventListener(ProgressEvent.PROGRESS))
			urlLoader.removeEventListener(ProgressEvent.PROGRESS, onLoadProgress);
	}
	
	private static var _context:LoaderContext;
	private static function get context():LoaderContext
	{
		if(!_context)
			_context = new LoaderContext(Ldr.policyFileCheck);
		_context.imageDecodingPolicy = ImageDecodingPolicy.ON_LOAD;
		return _context;
	}
	
	public function destroy():void
	{
		
	}
}
package  axl.utils
{
	/**
	 * [axldns free coding 2015]
	 */
	import flash.display.Bitmap;
	import flash.display.Loader;
	import flash.events.Event;
	import flash.media.Sound;
	import flash.net.URLLoader;
	import flash.system.System;
	import flash.utils.getTimer;
	
	/**
	 * <h1>Singletone files loader </h1>
	 * It 
	 * <ul>
	 * <li>loads files from local and remote directories - supports relative paths on both (general rules apply)</li>
	 * <li>looks up for user defined alternative directories (if file not found) in user defined order</li>
	 * <li>stores to hdd (AIR) on various conditions, including date comparison, file-directory-extension filters, user defined filters.</li>
	 * <li>Supports multi queues with various and mixed types of addressing (arrays, vectors with/or File class instances, strings of paths and sub-paths</li>
	 * <li>provides detailed info about progress and full controll on loading process (pause, stop, resume, queues/files re-index)</li>
	 * <li>processes commonly known data to expose usable forms (images, sounds, xmls, json) but leaves the rest un-touched.</li>
	 * </ul>
	 * <br>All that within one line of code, more ! with just one function! That's it. Don't need to learn anything else. Easily accesible without instantiation, 
	 * anywhere in your code just like <code>Ldr.load()</code> 
	 * <br><br>
	 * <h2>Singleton asset manager</h2>
	 * All objects are also super simple to access with just one command, anywhere from the code just like <code>Ldr.getMe()</code> 
	 * This Ldr assumes you know what you're doing, and if you're dealing with files, you want to call 'file.txt' rather than 'file'.
	 * <br> You can load and get file.png, file.jpg, file.atf, file.xml, file.txt and call them all whenever you like without worrying of anything else. 
	 * <br>Properly set up, even three lines of code can make a robust solution for assets update managed fully server side (mobile apps).
	 * <br>Full controll on loading process (pause, stop, resume, queues re-index) error handling, verbose mode
	 * 
	 *
	 */
	public class Ldr
	{
		
		public static function log(...args):void { if(_verbose is Function) _verbose.apply(null,args) }
		public static function set verbose(func:Function):void { _verbose = func = Req.verbose = func }
		private static var _verbose:Function;
		private static const defaultValue:String = ":default";
		
		//verbose = trace;
		
		private static var objects:Object = {};
		private static var urlLoaders:Object = {};
		private static var loaders:Object = {};
		private static var requests:Vector.<Req> = new Vector.<Req>();
		
		Req.loaders = loaders;
		Req.objects = objects;
		Req.urlLoaders = urlLoaders;
		
		private static var IS_LOADING:Boolean;
		public static var policyFileCheck:Boolean;
		
		
		/**
		 * (AIR only)
		 * 
		 *  @default  File.applicationStorageDirectory
		 * 
		 *  @see Ldr#load
		 *  @see Ldr#defaultOverwriteBehaviour
		 */
		public static var defaultStoreDirectory:Object = Req.fileInterfaceAvailable ? Req.FileClass.applicationStorageDirectory : null;
		
		/**
		 * (AIR only)
		 * Defines what files to overwrite if path where the file was loaded from is different to store directory.
		 * <br>This behaviour can be overriden by specifing appropriate load argument (see <i>load</i> 
		 * and <i>load</i> desc). 
		 * <ul>
		 * <li><u>all</u> - all conflict files will be overwritten</li>
		 * <li><u>none</u>, <u>null</u> or incorrect values - no overwriting at all</li> 
		 * <li><u>networkOnly</u> - only files loaded from paths starting like <i>http*</i> or <i>ftp*</i> will be overwritten</li>
		 * <li><u>olderThan_<i>unixTimestamp</i></u></li> -e.g. to overwrite only files older than midday 1 APR 2015 use <code>olderThan_1427889600</code>
		 * <li><u><code>Array/Vector/Directory</code></u></li> - only contents present in specified list of paths, list of files, specified directory
		 * will get owerwritten</li>
		 * <li><u>customFilter</u> - <code>function(existingFile:File):Boolean</code> let you decide for every particular file
		 * true - overrwrite, false - dont. Performance is on you in this case
		 * </ul>
		 * 
		 * @default networkOnly
		 * 
		 * @see Ldr#load
		 */
		public static var defaultStoringBehaviour:Object = '';
		
		
		/**
		 * defaultPathPrefixes allow you to look up for files to load in any number of directories in a single call.
		 * <b>Every</b> load call is prefixed but prefix can also be an empty string.
		 * <br>This behaviour can be overriden by specifing appropriate load argument (see load and load desc). 
		 *<br><br>
		 * Mixing <i>File</i> class constatns and domain addresses can set a nice flow with easily updateable set of assets and fallbacks.
		 * <br>
		 * <code>
		 * defaultPathPrefixes[0] = File.applicationStorageDirectory;<br>
		 * defaultPathPrefixes[1] = "http://domain.com/app";<br>
		 * defaultPathPrefixes[2] = File.applicationDirectory.nativePath;<br>
		 * <br>
		 * Ldr.load("/assets/example.file",onComplete);
		 * </code>
		 * <br>to check 
		 * <br><strong>app-storage:/assets/example.file</strong> onError:
		 * <br><strong>http://domain.com/app/assets/example.file</strong> onError
		 * <br><strong>app:/assets/example.fle</strong> onError : onComplete(null);
		 * <br><br>Highly recommended to push
		 * <br><code><i>root</i>.loaderInfo.url.substr(0,<i>root</i>.loaderInfo.url.lastIndexOf('/')</code>
		 * <br>for web apps.
		 * <br>relative paths are allowed with standard ActionsScirpt rules.
		 * @see Ldr#load */
		public static var defaultPathPrefixes:Object = [];
		
		/** <code>true</code>: If element's subpath matches <code>/^(http:|https:|ftp:|ftps:)/i</code>
		 * Ldr will try to load subpath only.
		 * <br><code>false</code>: regular behaviour where url = prefix[i] + subpath[j]
		 * <br>default: <code>true</code> * */
		public static function set networkOverPrefixes(v:Boolean):void { Req.networkOverPrefixes }
		public static function get networkOverPrefixes():Boolean { return Req.networkOverPrefixes }
		
		/** tells you if any loading is in progress */
		public static function get isLoading():Boolean 	{ return (numQueues > 0) &&  requests[0].isLoading }
		
		/** returns number of queues including current one */
		public static function get numQueues():int { return requests.length }
		
		/** returns number of elelements remained to load within current queue. 0 if there is no current queue */
		public static function get numCurrentRemaining():int { return (numQueues > 0) ? requests[0].numRemaining : 0}
		
		/** returns number of elements that has been originally scheduled to load. 0 if there is no current queue */
		public static function get numCurrentQueued():int { return (numQueues > 0) ? requests[0].numQueued : 0}
		
		/** returns number of successfully loaded elements in current queue. 0 if there is no current queue */
		public static function get numCurrentLoaded():int { return (numQueues > 0) ? requests[0].numLoaded : 0}
		
		/** returns number of elements that failed to load within current queue. 0 if there is no current queue */
		public static function get numCurrentSkipped():int { return (numQueues > 0) ? requests[0].numSkipped : 0}
		
		/** returns number of all remainig elements in all queues. Rolls back to 0 when all queues are done*/
		public static function get numAllRemaining():int { return Req.numAllRemaining }
		
		/** returns number of all originally queued elements in all queues. Rolls back to 0 once all queues are done. */
		public static function get numAllQueued():int { return Req.numAllQueued }
		
		/** returns number of all successfully loaded elements in all queues.  Rolls back to 0 once all queues are done. */
		public static function get numAllLoaded():int { return Req.numAllLoaded }
		
		/** returns number of all elements that failed to load within all queues. Rolls back to 0 once all queues are done. */
		public static function get numAllSkipped():int { return Req.numAllSkipped } 
		
				
		/** 
		 * adds path, file or list to load to current queue. 
		 * This is not preffered method for adding elelments to queue since <code>Ldr.load</code> accepts arrays, vectors, xmls. 
		 * <br>Use <i>addToCurrentQueue</i> when you need to inject to current. However,
		 * If current queue does not exist, this method creates one, and waits for <code>Ldr.load(null,..your args)</code> once you're done with adding,
		 * but <b>BEWARE</b>: Every later call to Ldr.load with specified pathList will be hold (queued) and won't start until you finalize this one 
		 * with <code>Ldr.load(null,..your args)</code>
		 * @return number of elements addded
		 * 
		 * @see Ldr#load
		 */
		public static function addToCurrentQueue(resourceOrList:Object):int
		{
			if(numQueues > 0) return requests[0].addPaths(resourceOrList);
			else
			{
				requests.push(new Req());
				return requests[0].addPaths(resourceOrList);
			}
		}
		
		/**  removes path, file or list to remove from current queue. 
		 @return number of elements removed*/
		public static function removeFromCurrentQueue(resourceOrList:Object):int
		{
			return isLoading ? requests[0].removePaths(resourceOrList) : 0;
		}
		
		
		/**
		 * Main function to get resource reference.<br>
		 * 
		 * <ul>
		 * <li>flash.disply.DisplayObject / Bitmap for jpg, jpeg, png, gif</li>
		 * <li>flash.media.Sound for mp3</li>
		 * <li> String / ByteArray / UTF for any binary (xml, json, txt, atf, etc..)
		 * <ul>
		 * @param v : filename with extension but without subpath. 
		 * <br> Resource names are formed based on path you <code>addToQueue</code> 
		 * or passed directly to <code>load</code> array
		 * @return null / undefined if asset is not loaded or data as above if loaded:<br>
		 * 
		 * @see Ldr#load
		 * @see Ldr#defaultPathPrefixes
		 */
		public static function getAny(v:String):Object { return objects[v] || getmeFromPath(v) }
		private static function getmeFromPath(v:String):Object
		{
			var i:int = v.lastIndexOf('/')+1, j:int = v.lastIndexOf('\\')+1;
			return objects[v.substr(i>j?i:j)];
		}
		
		public static function getBitmap(v:String):Bitmap { return getAny(v) as Bitmap }
		public static function getXML(v:String):XML { return getAny(v) as XML }
		public static function getJSON(v:String):Object { return getAny(v) }
		public static function getSound(v:String):Sound { return getAny(v) as Sound }
		public static function getMatching(regexp:String,target:Array=null, onlyTypes:Array=null):Array
		{
			target = target || [];
			var ti:int = target.length;
			for (var s:String in objects)
				if(s.match(regexp))
					target[ti++] = objects[s];
			if(onlyTypes is Array)
				for(;ti-->0;)
					for(var c:Class in onlyTypes)
						if(!(target[ti] is c))
							target.splice(ti++,1);
			return target;
		}
		public static function getNames(regexp:String='',target:Vector.<String>=null):Vector.<String>
		{
			target = target || new Vector.<String>();
			var ti:int = target.length;
			for (var s:String in objects)
				if(s.match(regexp))
					target[ti++] = s;
			return target;
		}
			
		/**
		 * Loads all assets <strong>synchroniously</strong> from array of paths or subpaths,
		 * checks for alternative directories, stores loaded files to directories (AIR only).
		 * It does not allow to load same asset twice. Use <code>Ldr.unload</code> to remove previously loaded files.
		 *
		 * @param resources : Basic types: <code>String, File, XML, XMLList</code> 
		 * or collections: <code>Array, Vector</code> of basic types. 
		 * <br>Basic elements must always point to file with an extension. 
		 * eg.: <code> ["/assets/images/a.jpg", "http://abc.de/fg.hi"]</code> 
		 * <br>or: (AIR) <code> File.applicationStorgeDirectory.getDirectoryListing()</code>
		 * Exception is File. If it points to directory, whole directory will be scanned recursively. 
		 * <br> Resources can be mixed together and embed to the reasonable level of depth - lists are parsed recursively too!
		 * <br> XML nodes may be of two names: files and file. files attribute <i>dir</i> will be prefixed to every value of file node inside it.
		 * <pre>
		 * < files dir="/assets">
		 * 	< file>/sounds/one.mp3< /file>
		 *  	< files dir="images">
		 * 		< file>two.png< /file>
		 * 		< file>two.jpg< /file>
		 * 	< /files>
		 * < /files>
		 * < file>/config/workflow/init.xml< /file>
		 * </pre>
		 * This would queue:
		 * <br>/assets/sounds/one.mp3
		 * <br>/asset/images/two.png
		 * <br>/assets/images/two.jpg
		 * <br>/config/workflow/init.xml
		 * 
		 * @param onComplete : function to execute once queue is done. this suppose to execute always, 
		 * regardles of issues with particular asssets. Exception is calling <code>Ldr.load(null, ..anyArgs)</code>
		 * while queue is already loading. This prevents before overwriting listeners and/or dispatching 
		 * when actually not done. 
		 * 
		 * @param individualComplete : <code>function(loadedAssetName:String)</code> this function 
		 * may not be executed if loader can't resolve either prefix  or path to resource, 
		 * but it is executed if loading failes - 
		 * <code>Ldr.getAny(loadedAssetName)</code> would return <code>null</code> in this case.
		 * As long as you pass correct resource types, function should always get executed.
		 * <br>individualComplete function will get executed only once for one item, 
		 * regardless of how many prefixes has been checked for it before.
		 * 
		 * @param onProgress : function which should accept two arguments:
		 * <ul>
		 * 	<li><code>Number</code> - bytesLoaded / bytesTotal of current asset
		 * 	<li><code>String</code> - name of currently loaded element
		 * </ul>
		 * To get detailed info of queue(s) status, whenever you need it query <code>Ldr.num^</code> getters
		 * Don't worry - there are no calculations on query time - values are being updated only when queue(s) status changes.
		 * 
		 * @param pathPrefixes: resource or resource list pointing to directories. 
		 * These values will be prefixed to <code>resources</code> defined elemements.
		 * Simplyfing, final patch will be formed as 
		 * <code> pathPrefixes[i] + resources[j] </code> 
		 * If loading fails, pathPrefixes index will keep increassing until 
		 * a) resource will get loaded or b) pathPrefixes index will reach maximum value.
		 * In both cases pathPrefix index will roll back to 0 for the next element. 
		 * Process applies to every queued item, therefore use your pathPrefixes wisely.
		 * Object is parsed simmilar way as <code>resources</code> argument but: 
		 * <br><b>1</b> pathPrefixes must not point to files (directories only)
		 * <br><b>2</b> pathPrefixes can also be set following way:
		 * <ul>
		 * 	<li><code>null</code> will match pathList only (empty prefix adds itself)</li>
		 * 	<li><code>Ldr.defaultValue</code> uses <u>Ldr.defaultPathPrefixes</u></li>
		 * </ul>
		 * 
		 * @param storeDirectory (AIR): 
		 * Defines where to store loaded files if <code>storingBehaviour</code> allows to do so.
		 *  If value can't be interpreted as storable directory - <code>null</code> will be assigned. E.g.:<br>
		 * 	 <code>
		 * 	Ldr.load("/assets/image.png",null,null,null,"http://domain.com",File.applicationStorageDirectory,/""/);
		 * 	</code>
		 * <br>would load: http://domain.com/assets/image.png
		 * <br>would save: app-storage:/assets/image.png
		 * <ul>
		 * 	<li><code>Ldr.defaultValue</code> uses <u>Ldr.defaultStoreDirectory</u></li>
		 * 	<li><code>String</code> tries to resolve path
		 * 	<li><code>File</code> tries to resole path
		 * 	<li><code>null</code> and/or other incorrect values - disables storing</li>
		 * </ul>
		 * 
		 * @param storingBehaviour (AIR):
		 * 	<ul>
		 * <li><code>Ldr.behaviours.default</code> will perform using <u>Ldr.defaultStoringBehaviour</u> values.
		 * 	<li><code>RegExp</code> particular resource will be stored in storeDirectory
		 *  	if its URL matches your your RegExp. Good scenario to store network updated files only by 
		 * 		passing <code>/^(http:|https:|ftp:|ftps:)/i</code> or to filter storing by extensions. 
		 * 		<br>Pass RegExp('') to store/overwrite all files from this queue.
		 * 		<br>Define storeDirectory as <code>null</code> to disable storing files from this queue.
		 *  <li><code>Date</code> or <code>Number</code> where number is unix timestamp. This stores files if 
		 *		<br> a) file does not exist in storeDirectory yet
		 *		<br> b) your date is greater than existing file modification date.</li>
		 * 	<li><code>function(existing:File, loadedFrom:String):File</code> - 
		 * 		<br>This function will be called for every element loaded from address different to storeDirectory. 
		 * 		This allows you to decide if file should get saved/overwritten and on what path too. 
		 * 		If you pass null, directory or any incorrect value - file won't be stored. If you pass any valid file, data will be stored.
		 * 		Performance is on you in this case.
		 * </ul>
		 * @return index of the queue this request has been placed on. -1 if resources is null
		 *  and and tere are no queues to process
		 * 
		 * @see Ldr#defaultPathPrefixes
		 * @see Ldr#defaultStoreDirectory
		 * @see Ldr#defaultOverwriteBehaviour
		 */
		public static function load(resources:Object=null, onComplete:Function=null, individualComplete:Function=null
												,onProgress:Function=null, pathPrefixes:Object=Ldr.defaultValue, 
												 storeDirectory:Object=Ldr.defaultValue, storingBehaviour:Object=Ldr.defaultValue):int
		{
			log("[Ldr] request load. State:", state);
			var req:Req, id:int = 0, startTime:int = getTimer();
			if(resources == null)
			{
				if(requests.length < 1) return (onComplete is Function) ? onComplete() : -1;
				else if(requests[0].isLoading) return 0;
				else req = requests[0];
			}
			else
			{
				req = new Req();
				id = requests.push(req)-1;
			}
			
			if(Req.fileInterfaceAvailable)
			{
				req.storeDirectory = (storeDirectory == Ldr.defaultValue ? Ldr.defaultStoreDirectory : storeDirectory);
				req.storingBehaviour = (storingBehaviour == Ldr.defaultValue ? Ldr.defaultStoringBehaviour : storingBehaviour);
			}
				req.onComplete = onComplete;
				req.individualComplete = individualComplete;
				req.onProgress = onProgress;
				
				req.addPaths(resources);
				req.addPrefixes((pathPrefixes == Ldr.defaultValue ? Ldr.defaultPathPrefixes : pathPrefixes));
			if(!IS_LOADING)
			{
				req.addEventListener(flash.events.Event.COMPLETE, completeHandler);
				req.load();
			}
			IS_LOADING = true;
			return id;
			function completeHandler(e:Event):void
			{
				var st:String = state;
				var rComplete:Function = req.onComplete;
				requests.splice(id,1);
				req.removeEventListener(flash.events.Event.COMPLETE, completeHandler);
				req.destroy();
				req.currentQueueDone();
				
				IS_LOADING = (numQueues > 0);
				if(IS_LOADING)
				{
					log("[Ldr] current queue finished with state:", st, '\ntimer:', getTimer()-startTime, 'ms');
					req = requests[0];
					id = 0;
					req.addEventListener(flash.events.Event.COMPLETE, completeHandler);
					req.load();
				}
				else
				{
					Req.allQueuesDone();
					req = null;
					log("[Ldr] all queues finished. state:", st, '\ntimer:', getTimer()-startTime, 'ms');
				}
				if(rComplete is Function)
					rComplete();
				rComplete=null;
			}		
		}
		
		public static function get state():String
		{
			var s:String = String('-' + 
			'\n isLoading:' + isLoading + 
			'\n numQueues:' + numQueues + 
			'\n numAllQueued:' +  numAllQueued + 
			'\n numAllRemaining:' + numAllRemaining + 
			'\n numAllLoaded:' + numAllLoaded +
			'\n numAllSkipped:' + numAllSkipped +
			'\n numCurrentQueued:' + numCurrentQueued +  
			'\n numCurrentRemaining:' +  numCurrentRemaining + 
			'\n numCurrentLoaded:' + numCurrentLoaded +
			'\n numCurrentSkipped:' + numCurrentSkipped +
			'\n timestamp:' +  new Date().time + '\n-'
			);
			return s;
		}
		
		/**
		 * Unloads / clears / disposes loaded data, removes display objects from display list
		 * <br> It won't affect sub-instantiated elements (XMLs, Textures, JSON parsed objects) but will make them 
		 * unavailable to restore (e.g. Starling.handleLostContext)
		 */
		public static function unload(filename:String):void
		{
			var o:Object= objects[filename];
			var l:Loader = loaders[filename];
			var u:URLLoader = urlLoaders[filename];
			if(o)
			{
				if(o.hasOwnProperty('parent') && o.parent)
					o.parent.removeChild(o);
				if(o is Bitmap && o.bitmapData)
				{
					o.bitmapData.dispose();
					o.bitmapData = null;
				}
				else if (o is XML)
					flash.system.System.disposeXML(o as XML)
				try { o.close() } catch (e:*) {}
			}
			if(l)
			{
				if(l.hasOwnProperty('parent') && l.parent)
					l.parent.removeChild(l);
				if(l.loaderInfo)
					l.loaderInfo.bytes.clear();
				l.unload();
				l.unloadAndStop();
			}
			if(u && u.data)
				u.data.clear();
			
			o =null, l = null,u = null;
			objects[filename] = null;
			loaders[filename] = null;
			urlLoaders[filename] = null;
			delete urlLoaders[filename];
			delete loaders[filename];
			delete objects[filename];
		}
	}
}
