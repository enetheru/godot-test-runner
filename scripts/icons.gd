@tool
extends Resource

## Named textures and the size cache.
## [member tex] is filled by res/icons.tres.
## Callers preload that resource. There is no class name.

@export
var tex:Dictionary[StringName, Texture2D] = {}

var _sized_cache:Dictionary[String, Texture2D] = {}


## Texture from [member tex], or null if the key is missing.
func get_tex( name:StringName ) -> Texture2D:
	if not tex.has( name ):
		return null
	return tex[name]


## Resize or size-override [param source] so [method Texture2D.get_size]
## matches [param size].
func at_size( source:Texture2D, size:Vector2i ) -> Texture2D:
	if source == null:
		return null
	if size.x <= 0 \
	or size.y <= 0:
		return source
	var source_size:Vector2 = source.get_size()
	if int( source_size.x ) == size.x \
	and int( source_size.y ) == size.y:
		return source

	var key:String = "%s@%dx%d" % [str( source.get_rid().get_id() ), size.x, size.y]
	if _sized_cache.has( key ):
		return _sized_cache[key]

	var sized:Texture2D
	var img:Image = source.get_image()
	if img != null \
	and not img.is_empty():
		var copy:Image = img.duplicate()
		copy.resize( size.x, size.y, Image.INTERPOLATE_LANCZOS )
		sized = ImageTexture.create_from_image( copy )
	else:
		# DPITexture / compressed sources may not expose pixels.
		var fallback:ImageTexture = ImageTexture.new()
		var blank:Image = Image.create_empty( size.x, size.y, false, Image.FORMAT_RGBA8 )
		blank.fill( Color( 1, 1, 1, 0.4 ) )
		fallback.set_image( blank )
		fallback.set_size_override( size )
		sized = fallback

	_sized_cache[key] = sized
	return sized
