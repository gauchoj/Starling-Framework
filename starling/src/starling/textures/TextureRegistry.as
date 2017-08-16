package starling.textures
{
	/**
	 * @author Assukar
	 */
	public interface TextureRegistry
	{
		function register(name: String, texture: Texture, atlas: TextureAtlas): void

		function unregister(name: String): void;
	}
}