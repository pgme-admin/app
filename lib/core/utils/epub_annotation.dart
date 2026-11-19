/// A highlight or underline in an EPUB, tracked from the moment it is drawn.
///
/// Saving to the backend happens in the background, one request at a time
/// per annotation ([saving] is the queue). A tap on the annotation works
/// immediately, even before (or without) a server id.
class EpubAnnotation {
  EpubAnnotation({
    required this.cfi,
    required this.type,
    this.color = 'yellow',
    this.text = '',
    this.note,
  });

  final String cfi;

  /// 'highlight' or 'underline'.
  final String type;
  String color;
  String text;
  String? note;

  /// Backend rows for this annotation. More than one can exist for books
  /// annotated twice by older app versions; removing deletes them all.
  final List<String> serverIds = [];
  Future<void>? saving;
  bool removed = false;

  String get key => keyFor(type, cfi);
  bool get isHighlight => type == 'highlight';

  static String keyFor(String type, String cfi) => '$type|$cfi';
}
