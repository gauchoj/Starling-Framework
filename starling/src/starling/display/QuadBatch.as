// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.display
{
	import starling.core.RenderSupport;
	import starling.core.Starling;
	import starling.core.starling_internal;
	import starling.errors.MissingContextError;
	import starling.events.Event;
	import starling.filters.FragmentFilter;
	import starling.filters.FragmentFilterMode;
	import starling.textures.Texture;
	import starling.textures.TextureSmoothing;
	import starling.utils.VertexData;

	import com.assukar.airong.utils.Utils;

	import flash.display3D.Context3D;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.Program3D;
	import flash.display3D.VertexBuffer3D;
	import flash.errors.IllegalOperationError;
	import flash.geom.Matrix;
	import flash.geom.Matrix3D;
	import flash.geom.Rectangle;
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	
	use namespace starling_internal;
	
	/** Optimizes rendering of a number of quads with an identical state.
	 *
	 *  <p>The majority of all rendered objects in Starling are quads. In fact, all the default
	 *  leaf nodes of Starling are quads (the Image and Quad classes). The rendering of those
	 *  quads can be accelerated by a big factor if all quads with an identical state are sent
	 *  to the GPU in just one call. That's what the QuadBatch class can do.</p>
	 *
	 *  <p>The 'flatten' method of the Sprite class uses this class internally to optimize its
	 *  rendering performance. In most situations, it is recommended to stick with flattened
	 *  sprites, because they are easier to use. Sometimes, however, it makes sense
	 *  to use the QuadBatch class directly: e.g. you can add one quad multiple times to
	 *  a quad batch, whereas you can only add it once to a sprite. Furthermore, this class
	 *  does not dispatch <code>ADDED</code> or <code>ADDED_TO_STAGE</code> events when a quad
	 *  is added, which makes it more lightweight.</p>
	 *
	 *  <p>One QuadBatch object is bound to a specific render state. The first object you add to a
	 *  batch will decide on the QuadBatch's state, that is: its texture, its settings for
	 *  smoothing and blending, and if it's tinted (colored vertices and/or transparency).
	 *  When you reset the batch, it will accept a new state on the next added quad.</p>
	 *
	 *  <p>The class extends DisplayObject, but you can use it even without adding it to the
	 *  display tree. Just call the 'renderCustom' method from within another render method,
	 *  and pass appropriate values for transformation matrix, alpha and blend mode.</p>
	 *
	 *  @see Sprite
	 */
	public class QuadBatch extends DisplayObject
	{
		/** The maximum number of quads that can be displayed by one QuadBatch. */
		public static const MAX_NUM_QUADS:int = 16383;
		
		private static const QUAD_PROGRAM_NAME:String = "QB_q";
		
		public var mNumQuads:int;
		private var mSyncRequired:Boolean;
		private var mBatchable:Boolean;
		private var mForceTinted:Boolean;
		private var mOwnsTexture:Boolean;
		
		private var mTinted:Boolean;
		private var mTexture:Texture;
		private var mSmoothing:String;
		
		private var mVertexBuffer:VertexBuffer3D;
		private var mIndexData:Vector.<uint>;
		private var mIndexBuffer:IndexBuffer3D;
		
		/** The raw vertex data of the quad. After modifying its contents, call
		 *  'onVertexDataChanged' to upload the changes to the vertex buffers. Don't change the
		 *  size of this object manually; instead, use the 'capacity' property of the QuadBatch. */
		protected var mVertexData:VertexData;
		
		/** Helper objects. */
		private static var sHelperMatrix:Matrix = new Matrix();
		private static var sRenderAlpha:Vector.<Number> = new <Number>[1.0, 1.0, 1.0, 1.0];
		private static var sProgramNameCache:Dictionary = new Dictionary();
		
		/** Creates a new QuadBatch instance with empty batch data. */
		public function QuadBatch()
		{
			mVertexData = new VertexData(0, true);
			mIndexData = new <uint>[];
			mNumQuads = 0;
			mTinted = false;
			mSyncRequired = false;
			mBatchable = false;
			
			mForceTinted = false;
			mOwnsTexture = false;
			
			// Handle lost context. We use the conventional event here (not the one from Starling)
			// so we're able to create a weak event listener; this avoids memory leaks when people 
			// forget to call "dispose" on the QuadBatch.
			Starling.current.stage3D.addEventListener(Event.CONTEXT3D_CREATE, onContextCreated, false, 0, true);
		}
		
		/** Disposes vertex- and index-buffer. */
		public override function dispose():void
		{
			Starling.current.stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
			destroyBuffers();
			
			mVertexData.numVertices = 0;
			mIndexData.length = 0;
			mNumQuads = 0;
			
//			mIgnoreFilters = false;
			
			if (mTexture && mOwnsTexture)
				mTexture.dispose();
			
			super.dispose();
		}
		
		private function onContextCreated(event:Object):void
		{
			createBuffers();
		}
		
		/** Call this method after manually changing the contents of 'mVertexData'. */
		protected function onVertexDataChanged():void
		{
			mSyncRequired = true;
		}
		
		/** Creates a duplicate of the QuadBatch object. */
		public function clone():QuadBatch
		{
			var clone:QuadBatch = new QuadBatch();
			clone.mVertexData = mVertexData.clone(0, mNumQuads * 4);
			clone.mIndexData = mIndexData.slice(0, mNumQuads * 6);
			clone.mNumQuads = mNumQuads;
			clone.mTinted = mTinted;
			clone.mTexture = mTexture;
			clone.mSmoothing = mSmoothing;
			clone.mSyncRequired = true;
			clone.blendMode = blendMode;
			clone.alpha = mAlpha;
			
//			clone.mIgnoreFilters = mIgnoreFilters;
			return clone;
		}
		
		private function expand():void
		{
			var oldCapacity:int = this.capacity;
			if (oldCapacity >= MAX_NUM_QUADS) throw new Error("Exceeded maximum number of quads!");
			this.capacity = oldCapacity < 8 ? 16 : oldCapacity * 2;
		}
		
		// DEPRECATED ASSUKAR CHANGED to return a boolean
		//private function createBuffers():void//Boolean
		private function createBuffers():Boolean 
		{
			destroyBuffers();
			
			var numVertices:int = mVertexData.numVertices;
			var numIndices:int = mIndexData.length;
			var context:Context3D = Starling.context;
			
			if (numVertices == 0) return true;// true;
			if (context == null) throw new MissingContextError();
			
			try
			{
				mVertexBuffer = context.createVertexBuffer(numVertices, VertexData.ELEMENTS_PER_VERTEX);
				mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, numVertices);
				mIndexBuffer = context.createIndexBuffer(numIndices);
				mIndexBuffer.uploadFromVector(mIndexData, 0, numIndices);
				mSyncRequired = false;
			}
			catch (e:Error)
			{
				mSyncRequired = true;
				mVertexBuffer = null;
				Utils.log("QuadBatch.createBuffers PROBLEM RENDERING numVertices=" + numVertices + " error=" + e.errorID + " frameCount=" + Starling.current.frameCount);
				if (e.errorID != 3672) throw e;
				return false;
			}
			
			return true;
		}
		
		private function destroyBuffers():void
		{
			if (mVertexBuffer)
			{
				mVertexBuffer.dispose();
				mVertexBuffer = null;
			}
			
			if (mIndexBuffer)
			{
				mIndexBuffer.dispose();
				mIndexBuffer = null;
			}
		}
		
		/** Uploads the raw data of all batched quads to the vertex buffer. */
		// ASSUKAR CHANGED to return a boolean 
		private function syncBuffers():Boolean
		{
			if (mVertexBuffer == null)
			{
				return createBuffers();
			}
			else
			{
				// as last parameter, we could also use 'mNumQuads * 4', but on some
				// GPU hardware (iOS!), this is slower than updating the complete buffer.
				mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, mVertexData.numVertices);
				mSyncRequired = false;
				return true;
			}
		}
		
		// obj-tion
		private var pma1:Boolean, context1:Context3D, tinted1:Boolean;
		
		/** Renders the current batch with custom settings for model-view-projection matrix, alpha
		 *  and blend mode. This makes it possible to render batches that are not part of the
		 *  display list. */
		public function renderCustom(mvpMatrix:Matrix3D, parentAlpha:Number = 1.0, blendMode:String = null):void
		{
			if (mNumQuads == 0) return;
			if (mSyncRequired && !syncBuffers()) return;
			
			pma1 = mVertexData.mPremultipliedAlpha;
			context1 = Starling.context;
			tinted1 = mTinted || (parentAlpha != 1.0);
			
			sRenderAlpha[0] = sRenderAlpha[1] = sRenderAlpha[2] = pma1 ? parentAlpha : 1.0;
			sRenderAlpha[3] = parentAlpha;
			
			RenderSupport.setBlendFactors(pma1, blendMode ? blendMode : this.blendMode);
			
			context1.setProgram(getProgram(tinted1));
			context1.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, sRenderAlpha, 1);
			context1.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 1, mvpMatrix, true);
			context1.setVertexBufferAt(0, mVertexBuffer, VertexData.POSITION_OFFSET, Context3DVertexBufferFormat.FLOAT_2);
			
			if (mTexture == null || tinted1)
				context1.setVertexBufferAt(1, mVertexBuffer, VertexData.COLOR_OFFSET, Context3DVertexBufferFormat.FLOAT_4);
			
			if (mTexture)
			{
				context1.setTextureAt(0, mTexture.base);
				context1.setVertexBufferAt(2, mVertexBuffer, VertexData.TEXCOORD_OFFSET, Context3DVertexBufferFormat.FLOAT_2);
			}
			
			context1.drawTriangles(mIndexBuffer, 0, mNumQuads * 2); 
			
			if (mTexture)
			{
				context1.setTextureAt(0, null);
				context1.setVertexBufferAt(2, null);
			}
			
			context1.setVertexBufferAt(1, null);
			context1.setVertexBufferAt(0, null);
		}
		
		/** Resets the batch. The vertex- and index-buffers remain their size, so that they
		 *  can be reused quickly. */
		public function reset():void
		{
			if (mTexture && mOwnsTexture) mTexture.dispose();
			mNumQuads = 0;
			mTexture = null;
			mSmoothing = null;
			mSyncRequired = true;
		}
		
		/** Adds an image to the batch. This method internally calls 'addQuad' with the correct
		 *  parameters for 'texture' and 'smoothing'. */
		public function addImage(image:Image, parentAlpha:Number = 1.0, modelViewMatrix:Matrix = null, blendMode:String = null):void
		{
			addQuad(image, parentAlpha, image.texture, image.smoothing, modelViewMatrix, blendMode);
		}
		
		/** Adds a quad to the batch. The first quad determines the state of the batch,
		 *  i.e. the values for texture, smoothing and blendmode. When you add additional quads,
		 *  make sure they share that state (e.g. with the 'isStateChange' method), or reset
		 *  the batch. */
		public function addQuad(quad:Quad, parentAlpha:Number = 1.0, texture:Texture = null, smoothing:String = null, modelViewMatrix:Matrix = null, blendMode:String = null):void
		{
//			mIgnoreFilters = quad.ignoreFilters;
			
			if (modelViewMatrix == null)
				modelViewMatrix = quad.transformationMatrix;
			
			var alpha:Number = parentAlpha * quad.mAlpha;
			var vertexID:int = mNumQuads * 4;
			
			if (mNumQuads + 1 > mVertexData.numVertices / 4) expand();
			if (mNumQuads == 0)
			{
				this.blendMode = blendMode ? blendMode : quad.blendMode;
				mTexture = texture;
				mTinted = mForceTinted || quad.tinted || parentAlpha != 1.0;
				mSmoothing = smoothing;
				mVertexData.setPremultipliedAlpha(quad.premultipliedAlpha);
			}
			
			quad.copyVertexDataTransformedTo(mVertexData, vertexID, modelViewMatrix);
			
			if (alpha != 1.0)
				mVertexData.scaleAlpha(vertexID, alpha, 4);
			
			mSyncRequired = true;
			mNumQuads++;
		}
		
		// obj-tion
		private var alpha1:Number, vertexID1:int, numQuads1:int;		
		
		/** Adds another QuadBatch to this batch. Just like the 'addQuad' method, you have to
		 *  make sure that you only add batches with an equal state. */
		public function addQuadBatch(quadBatch:QuadBatch, parentAlpha:Number = 1.0, modelViewMatrix:Matrix = null, blendMode:String = null):void
		{
//			mIgnoreFilters = quadBatch.mIgnoreFilters;
			
			if (modelViewMatrix == null)
				modelViewMatrix = quadBatch.transformationMatrix;
			
			alpha1 = parentAlpha * quadBatch.mAlpha;
			vertexID1 = mNumQuads * 4;
			numQuads1 = quadBatch.mNumQuads;
			
			if (mNumQuads + numQuads1 > capacity) capacity = mNumQuads + numQuads1;
			if (mNumQuads == 0)
			{
				this.blendMode = blendMode ? blendMode : quadBatch.blendMode;
				mTexture = quadBatch.mTexture;
				mTinted = mForceTinted || quadBatch.mTinted || parentAlpha != 1.0;
				mSmoothing = quadBatch.mSmoothing;
				mVertexData.setPremultipliedAlpha(quadBatch.mVertexData.premultipliedAlpha, false);
			}
			
			quadBatch.mVertexData.copyTransformedTo(mVertexData, vertexID1, modelViewMatrix, 0, numQuads1 * 4);
			
			if (alpha1 != 1.0)
				mVertexData.scaleAlpha(vertexID1, alpha1, numQuads1 * 4);
			
			mSyncRequired = true;
			mNumQuads += numQuads1;
		}
		
		/** Indicates if specific quads can be added to the batch without causing a state change.
		 *  A state change occurs if the quad uses a different base texture, has a different
		 *  'tinted', 'smoothing', 'repeat' or 'blendMode' setting, or if the batch is full
		 *  (one batch can contain up to 16383 quads). */
		public function isStateChange(tinted:Boolean, parentAlpha:Number, texture:Texture, smoothing:String, blendMode:String, numQuads:int = 1, ignoreFilters:Boolean = false):Boolean
		{
			if (mNumQuads == 0) return false;
			else if (mNumQuads + numQuads > MAX_NUM_QUADS) return true; // maximum buffer size
			else if (mTexture == null && texture == null)
				return this.blendMode != blendMode;
			else if (mTexture != null && texture != null)
				return mTexture.base != texture.base || mTexture.repeat != texture.repeat || mSmoothing != smoothing || mTinted != (mForceTinted || tinted || parentAlpha != 1.0) || this.blendMode != blendMode;
			else return true;
		}
		
		// utility methods for manual vertex-modification
		
		/** Transforms the vertices of a certain quad by the given matrix. */
		public function transformQuad(quadID:int, matrix:Matrix):void
		{
			mVertexData.transformVertex(quadID * 4, matrix, 4);
			mSyncRequired = true;
		}
		
		/** Returns the color of one vertex of a specific quad. */
		public function getVertexColor(quadID:int, vertexID:int):uint
		{
			return mVertexData.getColor(quadID * 4 + vertexID);
		}
		
		/** Updates the color of one vertex of a specific quad. */
		public function setVertexColor(quadID:int, vertexID:int, color:uint):void
		{
			mVertexData.setColor(quadID * 4 + vertexID, color);
			mSyncRequired = true;
		}
		
		/** Returns the alpha value of one vertex of a specific quad. */
		public function getVertexAlpha(quadID:int, vertexID:int):Number
		{
			return mVertexData.getAlpha(quadID * 4 + vertexID);
		}
		
		/** Updates the alpha value of one vertex of a specific quad. */
		public function setVertexAlpha(quadID:int, vertexID:int, alpha:Number):void
		{
			mVertexData.setAlpha(quadID * 4 + vertexID, alpha);
			mSyncRequired = true;
		}
		
		/** Returns the color of the first vertex of a specific quad. */
		public function getQuadColor(quadID:int):uint
		{
			return mVertexData.getColor(quadID * 4);
		}
		
		/** Updates the color of a specific quad. */
		public function setQuadColor(quadID:int, color:uint):void
		{
			for (var i:int = 0; i < 4; ++i)
				mVertexData.setColor(quadID * 4 + i, color);
			
			mSyncRequired = true;
		}
		
		/** Returns the alpha value of the first vertex of a specific quad. */
		public function getQuadAlpha(quadID:int):Number
		{
			return mVertexData.getAlpha(quadID * 4);
		}
		
		/** Updates the alpha value of a specific quad. */
		public function setQuadAlpha(quadID:int, alpha:Number):void
		{
			for (var i:int = 0; i < 4; ++i) mVertexData.setAlpha(quadID * 4 + i, alpha);
			mSyncRequired = true;
		}
		
		/** Replaces a quad or image at a certain index with another one. */
		public function setQuad(quadID:Number, quad:Quad):void
		{
			var matrix:Matrix = quad.transformationMatrix;
			var alpha:Number = quad.mAlpha;
			var vertexID:int = quadID * 4;
			
			quad.copyVertexDataTransformedTo(mVertexData, vertexID, matrix);
			if (alpha != 1.0) mVertexData.scaleAlpha(vertexID, alpha, 4);
			
			mSyncRequired = true;
		}
		
		/** Calculates the bounds of a specific quad, optionally transformed by a matrix.
		 *  If you pass a 'resultRect', the result will be stored in this rectangle
		 *  instead of creating a new object. */
		public function getQuadBounds(quadID:int, transformationMatrix:Matrix = null, resultRect:Rectangle = null):Rectangle
		{
			return mVertexData.getBounds(transformationMatrix, quadID * 4, 4, resultRect);
		}
		
		// display object methods
		
		/** @inheritDoc */
		public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle = null):Rectangle
		{
			if (resultRect == null) resultRect = new Rectangle();
			
			var transformationMatrix:Matrix = targetSpace == this ? null : getTransformationMatrix(targetSpace, sHelperMatrix);
			
			return mVertexData.getBounds(transformationMatrix, 0, mNumQuads * 4, resultRect);
		}
		
		/** @inheritDoc */
		public override function render(support:RenderSupport, parentAlpha:Number):void
		{
			if (mNumQuads)
			{
				if (mBatchable)
					support.batchQuadBatch(this, parentAlpha);
				else
				{
					support.finishQuadBatch();
					support.raiseDrawCount();
					renderCustom(support.mvpMatrix3D, mAlpha * parentAlpha, support.blendMode);
				}
			}
		}
		
		// compilation (for flattened sprites)
		
		/** Analyses an object that is made up exclusively of quads (or other containers)
		 *  and creates a vector of QuadBatch objects representing it. This can be
		 *  used to render the container very efficiently. The 'flatten'-method of the Sprite
		 *  class uses this method internally. */
		public static function compile(object:DisplayObject, quadBatches:Vector.<QuadBatch>):void
		{
			compileObject(object, quadBatches, -1, new Matrix());
		}
		
		/** Naively optimizes a list of batches by merging all that have an identical state.
		 *  Naturally, this will change the z-order of some of the batches, so this method is
		 *  useful only for specific use-cases. */
		public static function optimize(quadBatches:Vector.<QuadBatch>):void
		{
			var batch1:QuadBatch, batch2:QuadBatch;
			for (var i:int = 0; i < quadBatches.length; ++i)
			{
				batch1 = quadBatches[i];
				for (var j:int = i + 1; j < quadBatches.length; )
				{
					batch2 = quadBatches[j];
					if (!batch1.isStateChange(batch2.tinted, 1.0, batch2.texture, batch2.smoothing, batch2.blendMode, 1, false))
					{
						batch1.addQuadBatch(batch2);
						batch2.dispose();
						quadBatches.splice(j, 1);
					}
					else ++j;
				}
			}
		}
		
		private static function compileObject(object:DisplayObject, quadBatches:Vector.<QuadBatch>, quadBatchID:int, transformationMatrix:Matrix, alpha:Number = 1.0, blendMode:String = null, ignoreCurrentFilter:Boolean = false):int
		{
//			if (object is Sprite3D) throw new IllegalOperationError("Sprite3D objects cannot be flattened");
			
			var i:int;
			var quadBatch:QuadBatch;
			var isRootObject:Boolean = false;
			var objectAlpha:Number = object.mAlpha;
			
			var container:DisplayObjectContainer = object as DisplayObjectContainer;
			var quad:Quad = object as Quad;
			var batch:QuadBatch = object as QuadBatch;
			var filter:FragmentFilter = object.filter;
			
			if (quadBatchID == -1)
			{
				isRootObject = true;
				quadBatchID = 0;
				objectAlpha = 1.0;
				blendMode = object.blendMode;
				ignoreCurrentFilter = true;
				if (quadBatches.length == 0) quadBatches[0] = new QuadBatch();
				else
				{
					quadBatches[0].reset();
					quadBatches[0].ownsTexture = false;
				}
			}
			
			if (filter && !ignoreCurrentFilter)
			{
				if (filter.mode == FragmentFilterMode.ABOVE)
				{
					quadBatchID = compileObject(object, quadBatches, quadBatchID, transformationMatrix, alpha, blendMode, true);
				}
				
				quadBatchID = compileObject(filter.compile(object), quadBatches, quadBatchID, transformationMatrix, alpha, blendMode);
				
				// textures of a compiled filter need to be disposed!
				quadBatches[quadBatchID].ownsTexture = true;
				
				if (filter.mode == FragmentFilterMode.BELOW)
				{
					quadBatchID = compileObject(object, quadBatches, quadBatchID, transformationMatrix, alpha, blendMode, true);
				}
			}
			else if (container)
			{
				var numChildren:int = container.numChildren;
				var childMatrix:Matrix = new Matrix();
				
				for (i = 0; i < numChildren; ++i)
				{
					var child:DisplayObject = container.getChildAt(i);
					if (child.hasVisibleArea)
					{
						var childBlendMode:String = child.blendMode == BlendMode.AUTO ? blendMode : child.blendMode;
						childMatrix.copyFrom(transformationMatrix);
						RenderSupport.transformMatrixForObject(childMatrix, child);
						quadBatchID = compileObject(child, quadBatches, quadBatchID, childMatrix, alpha * objectAlpha, childBlendMode);
					}
				}
			}
			else if (quad || batch)
			{
				var texture:Texture;
				var smoothing:String;
				var tinted:Boolean;
				var numQuads:int;
//				var ignoreFilters:Boolean;
				
				if (quad)
				{
					var image:Image = quad as Image;
					texture = image ? image.texture : null;
					smoothing = image ? image.smoothing : null;
					tinted = quad.tinted;
					numQuads = 1;
//					ignoreFilters = quad.ignoreFilters;
				}
				else
				{
					texture = batch.mTexture;
					smoothing = batch.mSmoothing;
					tinted = batch.mTinted;
					numQuads = batch.mNumQuads;
//					ignoreFilters = batch.ignoreFilters;
				}
				
				quadBatch = quadBatches[quadBatchID];
				
				if (quadBatch.isStateChange(tinted, alpha * objectAlpha, texture, smoothing, blendMode, numQuads, false))//ignoreFilters))
				{
					quadBatchID++;
					if (quadBatches.length <= quadBatchID) quadBatches.push(new QuadBatch());
					quadBatch = quadBatches[quadBatchID];
					quadBatch.reset();
					quadBatch.ownsTexture = false;
				}
				
				if (quad)
					quadBatch.addQuad(quad, alpha, texture, smoothing, transformationMatrix, blendMode);
				else
					quadBatch.addQuadBatch(batch, alpha, transformationMatrix, blendMode);
			}
			else
			{
				throw new Error("Unsupported display object: " + getQualifiedClassName(object));
			}
			
			if (isRootObject)
			{
				// remove unused batches
				for (i = quadBatches.length - 1; i > quadBatchID; --i)
					quadBatches.pop().dispose();
			}
			
			return quadBatchID;
		}
		
		// properties
		
		/** Returns the number of quads that have been added to the batch. */
		final public function get numQuads():int  { return mNumQuads; }
		
		/** Indicates if any vertices have a non-white color or are not fully opaque. */
		public function get tinted():Boolean  { return mTinted || mForceTinted; }
		
		/** The texture that is used for rendering, or null for pure quads. Note that this is the
		 *  texture instance of the first added quad; subsequently added quads may use a different
		 *  instance, as long as the base texture is the same. */
		public function get texture():Texture  { return mTexture; }
		
		/** The TextureSmoothing used for rendering. */
		public function get smoothing():String  { return mSmoothing; }
		
		/** Indicates if the rgb values are stored premultiplied with the alpha value. */
		public function get premultipliedAlpha():Boolean  { return mVertexData.premultipliedAlpha; }
		
		/** Indicates if the batch itself should be batched on rendering. This makes sense only
		 *  if it contains only a small number of quads (we recommend no more than 16). Otherwise,
		 *  the CPU costs will exceed any gains you get from avoiding the additional draw call.
		 *  @default false */
		public function get batchable():Boolean  { return mBatchable; }
		
		public function set batchable(value:Boolean):void  { mBatchable = value; }
		
		/** If enabled, the QuadBatch will always be rendered with a tinting-enabled fragment
		 *  shader and the method 'isStateChange' won't take tinting into account. This means
		 *  fewer state changes, but also a slightly more complex fragment shader for non-tinted
		 *  quads. On modern hardware, that's not a problem, and you'll avoid unnecessary state
		 *  changes. However, on old devices like the iPad 1, you should be careful with this
		 *  setting. @default false
		 */
		public function get forceTinted():Boolean  { return mForceTinted; }
		
		public function set forceTinted(value:Boolean):void
		{
			mForceTinted = value;
		}
		
		/** If enabled, the texture (if there is one) will be disposed when the QuadBatch is. */
		public function get ownsTexture():Boolean  { return mOwnsTexture; }
		
		public function set ownsTexture(value:Boolean):void  { mOwnsTexture = value; }
		
		/** Indicates the number of quads for which space is allocated (vertex- and index-buffers).
		 *  If you add more quads than what fits into the current capacity, the QuadBatch is
		 *  expanded automatically. However, if you know beforehand how many vertices you need,
		 *  you can manually set the right capacity with this method. */
		public function get capacity():int  { return mVertexData.numVertices / 4; }
		
		public function set capacity(value:int):void
		{
			var oldCapacity:int = capacity;
			
			if (value == oldCapacity) return;
			else if (value == 0) throw new Error("Capacity must be > 0");
			else if (value > MAX_NUM_QUADS) value = MAX_NUM_QUADS;
			if (mNumQuads > value) mNumQuads = value;
			
			mVertexData.numVertices = value * 4;
			mIndexData.length = value * 6;
			
			for (var i:int = oldCapacity; i < value; ++i)
			{
				mIndexData[int(i * 6)] = i * 4;
				mIndexData[int(i * 6 + 1)] = i * 4 + 1;
				mIndexData[int(i * 6 + 2)] = i * 4 + 2;
				mIndexData[int(i * 6 + 3)] = i * 4 + 1;
				mIndexData[int(i * 6 + 4)] = i * 4 + 3;
				mIndexData[int(i * 6 + 5)] = i * 4 + 2;
			}
			
			destroyBuffers();
			mSyncRequired = true;
		}
		
		// program management
		
		private var target:Starling, programName:String, program:Program3D, vertexShader:String, fragmentShader:String;
		
		private function getProgram(tinted:Boolean):Program3D
		{
			if (!target) target = Starling.current;
			programName = QUAD_PROGRAM_NAME;
			if (mTexture) programName = getImageProgramName(tinted, mTexture.repeat, mTexture.format, mSmoothing);
			program = target.getProgram(programName);
			
			if (!program)
			{
				// this is the input data we'll pass to the shaders:
				// 
				// va0 -> position
				// va1 -> color
				// va2 -> texCoords
				// vc0 -> alpha
				// vc1 -> mvpMatrix
				// fs0 -> texture
				
//				var vertexShader:String;
//				var fragmentShader:String;
				
				if (!mTexture) // Quad-Shaders
				{
					vertexShader = "m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mul v0, va1, vc0 \n";  // multiply alpha (vc0) with color (va1)
					
					fragmentShader = "mov oc, v0       \n";  // output color
				}
				else // Image-Shaders
				{
					vertexShader = tinted ? "m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mul v0, va1, vc0 \n" + // multiply alpha (vc0) with color (va1)
					"mov v1, va2      \n"   // pass texture coordinates to fragment program
					: "m44 op, va0, vc1 \n" + // 4x4 matrix transform to output clipspace
					"mov v1, va2      \n";  // pass texture coordinates to fragment program
					
					fragmentShader = tinted ? "tex ft1,  v1, fs0 <???> \n" + // sample texture 0
					"mul  oc, ft1,  v0       \n"   // multiply color with texel color
					: "tex  oc,  v1, fs0 <???> \n";  // sample texture 0
					
//					fragmentShader = fragmentShader.replace("<???>", RenderSupport.getTextureLookupFlags(mTexture.format, mTexture.mipMapping, mTexture.repeat, smoothing));
					fragmentShader = fragmentShader.replace("<???>", RenderSupport.getTextureLookupFlags(mTexture.format, mTexture.repeat, smoothing));
				}
				
				program = target.registerProgramFromSource(programName, vertexShader, fragmentShader);
			}
			
			return program;
		}
		
		static private var bitField:uint, name:String;
		
		private static function getImageProgramName(tinted:Boolean, repeat:Boolean = false, format:String = "bgra", smoothing:String = "bilinear"):String
		{
			bitField = 0;
			
			if (tinted) bitField |= 1;
//			if (mipMap) bitField |= 1 << 1;
			if (repeat) bitField |= 1 << 2;
			
			if (smoothing == TextureSmoothing.NONE) bitField |= 1 << 3;
			else if (smoothing == TextureSmoothing.TRILINEAR) bitField |= 1 << 4;
			
			if (format == Context3DTextureFormat.COMPRESSED) bitField |= 1 << 5;
			else if (format == "compressedAlpha") bitField |= 1 << 6;
			
			name = sProgramNameCache[bitField];
			
			if (name == null)
			{
				name = "QB_i." + bitField.toString(16);
				sProgramNameCache[bitField] = name;
			}
			
			return name;
		}
	}
}
