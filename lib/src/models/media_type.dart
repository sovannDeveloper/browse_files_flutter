/// The kind of asset a [MediaItem] describes.
///
/// The picker only ever deals in visual media; audio and documents arrive
/// through the file tab, which hands back paths rather than library assets.
enum MediaType {
  /// A still image.
  image,

  /// A video, which carries a duration.
  video;

  /// Reads the wire representation used on the platform channel.
  ///
  /// Throws [ArgumentError] for anything else: both ends of this channel ship
  /// in this package, so an unrecognised name is a bug here, not user input.
  static MediaType fromName(String? name) => switch (name) {
    'image' => MediaType.image,
    'video' => MediaType.video,
    _ => throw ArgumentError.value(name, 'name', 'unknown media type'),
  };
}
