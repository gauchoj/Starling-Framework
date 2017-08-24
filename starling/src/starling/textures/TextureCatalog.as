package starling.textures
{
	import com.assukar.airong.ds.HashSet;
	import com.assukar.airong.ds.LinkedList;
	import com.assukar.airong.utils.Singleton;
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
		
		private function dump(): void
		{
			var groups: HashSet = new HashSet();
			hashset.apply(function(texture: Texture): void
			{
				groups.push(texture.group);
			});
			
			var i: int = 0;
			groups.apply(function(group: String): void
			{
				var c: int = 0;
				var str: String = "";
				hashset.apply(function(texture: Texture): void
				{
					if (group == texture.group)
					{
						i++;
						c++;
						str += "   " + i + " " + texture.name + "\n"; 
					}
				});
				trace(">> " + group + " " + c);
				trace(str);
			});
			
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