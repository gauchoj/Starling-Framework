// =================================================================================================
//
//	Starling Framework
//	Copyright Gamua GmbH. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.textures
{
	import starling.core.RenderSupport;
	import starling.core.Starling;
	import starling.core.starling_internal;
	import starling.errors.MissingContextError;
	import starling.errors.NotSupportedError;
	import starling.events.Event;
	import starling.utils.Color;
	import starling.utils.execute;

	import com.assukar.airong.utils.Utils;

	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display3D.Context3D;
	import flash.display3D.textures.TextureBase;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.media.Camera;
	import flash.net.NetStream;
	import flash.utils.ByteArray;
	import flash.utils.getQualifiedClassName;

    use namespace starling_internal;

    /** A ConcreteTexture wraps a Stage3D texture object, storing the properties of the texture. */
    public class ConcreteTexture extends Texture
    {
        private static const TEXTURE_READY:String = "textureReady"; // defined here for backwards compatibility
        private var mBase:TextureBase;
        private var mFormat:String;
        private var mWidth:int;
        private var mHeight:int;
//        private var mMipMapping:Boolean;
        private var mPremultipliedAlpha:Boolean;
        private var mOptimizedForRenderTexture:Boolean;
        private var mScale:Number;
        private var mRepeat:Boolean;
        private var mOnRestore:Function;
        private var mDataUploaded:Boolean;
        private var mTextureReadyCallback:Function;
        
        /** helper object */
        private static var sOrigin:Point = new Point();
        
        /** Creates a ConcreteTexture object from a TextureBase, storing information about size,
         *  mip-mapping, and if the channels contain premultiplied alpha values. */
        function ConcreteTexture(base:TextureBase, format:String, width:int, height:int, 
				premultipliedAlpha:Boolean, optimizedForRenderTexture:Boolean=false, scale:Number=1, repeat:Boolean=false)
        {
            mScale = scale <= 0 ? 1.0 : scale;
            mBase = base;
            mFormat = format;
            mWidth = width;
            mHeight = height;
            mPremultipliedAlpha = premultipliedAlpha;
            mOptimizedForRenderTexture = optimizedForRenderTexture;
            mRepeat = repeat;
            mOnRestore = null;
            mDataUploaded = false;
            mTextureReadyCallback = null;
        }
        
        /** Disposes the TextureBase object. */
        public override function dispose():void
        {
            if (mBase)
            {
                mBase.removeEventListener(TEXTURE_READY, onTextureReady);
                mBase.dispose();
            }

            this.onRestore = null;
            super.dispose();
        }
        
        // texture data upload
        
        /** Uploads a bitmap to the texture. The existing contents will be replaced.
         *  If the size of the bitmap does not match the size of the texture, the bitmap will be
         *  cropped or filled up with transparent pixels */
        public function uploadBitmap(bitmap:Bitmap):void
        {
            uploadBitmapData(bitmap.bitmapData);
        }
        
        /** Uploads bitmap data to the texture. The existing contents will be replaced.
         *  If the size of the bitmap does not match the size of the texture, the bitmap will be
         *  cropped or filled up with transparent pixels */
        public function uploadBitmapData(data:BitmapData):void
        {
            var potData:BitmapData;
			
			try
			{
				data.width;
			}
			catch (e: Error)
			{
				Utils.log("name=" + name + " mWidth=" + mWidth + " mHeight=" + mHeight);
				throw e;
			}
			
            if (data.width != mWidth || data.height != mHeight)
            {
                potData = new BitmapData(mWidth, mHeight, true, 0);
                potData.copyPixels(data, data.rect, sOrigin);
                data = potData;
            }			
			
            if (mBase is flash.display3D.textures.Texture)
            {
                var potTexture:flash.display3D.textures.Texture = 
                    mBase as flash.display3D.textures.Texture;
					
					potTexture.uploadFromBitmapData(data);
            }
            else 
            {
                mBase["uploadFromBitmapData"](data);
            }
			
			
            if (potData) potData.dispose();
            mDataUploaded = true;
        }
		
        
        /** Uploads ATF data from a ByteArray to the texture. Note that the size of the
         *  ATF-encoded data must be exactly the same as the original texture size.
         *  
         *  <p>The 'async' parameter may be either a boolean value or a callback function.
         *  If it's <code>false</code> or <code>null</code>, the texture will be decoded
         *  synchronously and will be visible right away. If it's <code>true</code> or a function,
         *  the data will be decoded asynchronously. The texture will remain unchanged until the
         *  upload is complete, at which time the callback function will be executed. This is the
         *  expected function definition: <code>function(texture:Texture):void;</code></p>
         */
        public function uploadAtfData(data:ByteArray, offset:int=0, async:*=null):void
        {
            var isAsync:Boolean = async is Function || async === true;
            var potTexture:flash.display3D.textures.Texture = mBase as flash.display3D.textures.Texture;
            
            if (potTexture == null) throw new Error("This texture type does not support ATF data");
            
            if (async is Function)
            {
                mTextureReadyCallback = async as Function;
                mBase.addEventListener(TEXTURE_READY, onTextureReady);
            }
            
            potTexture.uploadCompressedTextureFromByteArray(data, offset, isAsync);
            mDataUploaded = true;
        }

        public function attachNetStream(netStream:NetStream, onComplete:Function=null):void
        {
            attachVideo("NetStream", netStream, onComplete);
        }

        public function attachCamera(camera:Camera, onComplete:Function=null):void
        {
            attachVideo("Camera", camera, onComplete);
        }

        internal function attachVideo(type:String, attachment:Object, onComplete:Function=null):void
        {
            const className:String = getQualifiedClassName(mBase);

            if (className == "flash.display3D.textures::VideoTexture")
            {
                mDataUploaded = true;
                mTextureReadyCallback = onComplete;
                mBase["attach" + type](attachment);
                mBase.addEventListener(TEXTURE_READY, onTextureReady);
            }
            else throw new Error("This texture type does not support " + type + " data");
        }

        private function onTextureReady(event:Object):void
        {
            mBase.removeEventListener(TEXTURE_READY, onTextureReady);
            execute(mTextureReadyCallback, this);
            mTextureReadyCallback = null;
        }
		
		
		public function uploadByteArray(data:ByteArray):void {
			
			var bytesOut:ByteArray = new ByteArray();
			data.position = 0;
			while (data.bytesAvailable) {
				var pixel:uint = data.readUnsignedInt();
				bytesOut.writeUnsignedInt(
					(pixel >> 24 & 0xff) > uint(0xff*.5) 
						? ((pixel & 0xff) << 24)
						  | ((pixel >> 8 & 0xff) << 16)
						  | ((pixel >> 16 & 0xff) << 8)
						  | (pixel >> 24 & 0xff)
						: 0x0					
				);
			}		
			
            if (mBase is flash.display3D.textures.Texture) {
                var potTexture:flash.display3D.textures.Texture = mBase as flash.display3D.textures.Texture;					
				potTexture.uploadFromByteArray(bytesOut, 0);				
            }else {
                mBase["uploadFromByteArray"](bytesOut, 0);
            }
			
            mDataUploaded = true;
			bytesOut.clear();
			data.clear();
        }
		
		
        
        // texture backup (context loss)
        
        private function onContextCreated():void 
        {
            // recreate the underlying texture & restore contents 
            createBase();
            if (mOnRestore != null) mOnRestore();
            
            // if no texture has been uploaded above, we init the texture with transparent pixels.
            if (!mDataUploaded) clear();
        }
        
        /** Recreates the underlying Stage3D texture object with the same dimensions and attributes
         *  as the one that was passed to the constructor. You have to upload new data before the
         *  texture becomes usable again. Beware: this method does <strong>not</strong> dispose
         *  the current base. */
        starling_internal function createBase():void
        {
            var context:Context3D = Starling.context;
            var className:String = getQualifiedClassName(mBase);
            
            if (className == "flash.display3D.textures::Texture")
                mBase = context.createTexture(mWidth, mHeight, mFormat, 
                                              mOptimizedForRenderTexture);
            else if (className == "flash.display3D.textures::RectangleTexture")
                mBase = context["createRectangleTexture"](mWidth, mHeight, mFormat,
                                                          mOptimizedForRenderTexture);
            else if (className == "flash.display3D.textures::VideoTexture")
                mBase = context["createVideoTexture"]();
            else
                throw new NotSupportedError("Texture type not supported: " + className);

            mDataUploaded = false;
        }
        
        /** Clears the texture with a certain color and alpha value. The previous contents of the
         *  texture is wiped out. Beware: this method resets the render target to the back buffer; 
         *  don't call it from within a render method. */ 
        public function clear(color:uint=0x0, alpha:Number=0.0):void
        {
            var context:Context3D = Starling.context;
            if (context == null) throw new MissingContextError();
            
            if (mPremultipliedAlpha && alpha < 1.0)
                color = Color.rgb(Color.getRed(color)   * alpha,
                                  Color.getGreen(color) * alpha,
                                  Color.getBlue(color)  * alpha);
            
            context.setRenderToTexture(mBase);
            
            // we wrap the clear call in a try/catch block as a workaround for a problem of
            // FP 11.8 plugin/projector: calling clear on a compressed texture doesn't work there
            // (while it *does* work on iOS + Android).
            
            try { RenderSupport.clear(color, alpha); }
            catch (e:Error) {}
            
            context.setRenderToBackBuffer();
            mDataUploaded = true;
        }
        
        // properties
        
        /** Indicates if the base texture was optimized for being used in a render texture. */
        public function get optimizedForRenderTexture():Boolean { return mOptimizedForRenderTexture; }
        
        /** If Starling's "handleLostContext" setting is enabled, the function that you provide
         *  here will be called after a context loss. On execution, a new base texture will
         *  already have been created; however, it will be empty. Call one of the "upload..."
         *  methods from within the callbacks to restore the actual texture data. */
        public function get onRestore():Function { return mOnRestore; }
        public function set onRestore(value:Function):void
        {
            Starling.current.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
            
            if (Starling.handleLostContext && value != null)
            {
                mOnRestore = value;
                Starling.current.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
            }
            else mOnRestore = null;
        }
        
        /** @inheritDoc */
        public override function get base():TextureBase { return mBase; }
        
        /** @inheritDoc */
        public override function get root():ConcreteTexture { return this; }
        
        /** @inheritDoc */
        public override function get format():String { return mFormat; }
        
        /** @inheritDoc */
        public override function get width():Number  { return mWidth / mScale;  }
        
        /** @inheritDoc */
        public override function get height():Number { return mHeight / mScale; }
        
        /** @inheritDoc */
        public override function get nativeWidth():Number { return mWidth; }
        
        /** @inheritDoc */
        public override function get nativeHeight():Number { return mHeight; }
        
        /** The scale factor, which influences width and height properties. */
        public override function get scale():Number { return mScale; }
        
        /** @inheritDoc */
//        public override function get mipMapping():Boolean { return mMipMapping; }
        
        /** @inheritDoc */
        public override function get premultipliedAlpha():Boolean { return mPremultipliedAlpha; }
        
        /** @inheritDoc */
        public override function get repeat():Boolean { return mRepeat; }
    }
}