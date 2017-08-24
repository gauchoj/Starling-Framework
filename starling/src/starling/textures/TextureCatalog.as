package starling.textures
{
	import com.assukar.airong.ds.HashSet;
	import com.assukar.airong.utils.Singleton;
	import com.assukar.airong.utils.Statics;
	import com.assukar.airong.utils.Utils;
	import flash.utils.setInterval;
	/**
	 * @author Assukar
	 */
	public class TextureCatalog
	{
		static internal const ACTIVE: Boolean = true;
		static public const ME: TextureCatalog = new TextureCatalog();
		
		function TextureCatalog()
		{
			Singleton.enforce(ME);
			
			CONFIG::DEBUG
			{			
				if (ACTIVE) setInterval(dump, 15000);
			}
		}
		
		private var hashset: HashSet = new HashSet();
		private var registers: int = 0;
		private var removals: int = 0;
		
		private function bytes(size: int): String
		{
			if (size < Statics.KB) return size+"b";
			else if (size < Statics.MB) return (size/Statics.KB).toFixed(0)+"Kb";
			else if (size < Statics.GB) return (size/Statics.MB).toFixed(1)+"Mb";
			else return (size/Statics.GB).toFixed(3)+"Gb";
		}
		
		private function dump(): void
		{
			var groups: HashSet = new HashSet();
			hashset.apply(function(texture: Texture): void
			{
				groups.push(texture.group);
			});
			
			var i: int = 0;
			var asize: uint = 0;
			groups.apply(function(group: String): void
			{
				var c: int = 0;
				var str: String = "";
				var size: uint = 0;
				hashset.apply(function(texture: Texture): void
				{
					if (group == texture.group)
					{
						i++;
						c++;
						size += texture.nativeWidth * texture.nativeHeight;
						str += "   " + i + " " + texture.name + " " + bytes(texture.nativeWidth * texture.nativeHeight) + "\n"; 
					}
				});
				asize += size;
				trace(">> " + group + " " + c + " " + bytes(size));
				trace(str);
			});
			
			Utils.print("ALL " + bytes(asize));
			Utils.print("registers=" + registers + " removals=" + removals);
		}
		
		internal function register(texture: Texture): void
		{
			registers++;
			hashset.push(texture);
		}
		
		internal function dispose(texture: Texture): void
		{
			removals++;
			hashset.removeObject(texture);
		}
	}
}