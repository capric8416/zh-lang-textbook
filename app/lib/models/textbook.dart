import 'dart:convert';

class Textbook {
  Textbook({
    required this.schemaVersion,
    required this.index,
    required this.contents,
    required this.highlights,
  }) : chaptersById = {
         for (final unit in contents)
           for (final chapter in unit.chapters) chapter.id: chapter,
       },
       nodesById = _indexNodes(contents),
       segmentsById = _indexSegments(contents);

  factory Textbook.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('教材 JSON 顶层必须是对象');
    }
    return Textbook.fromJson(decoded);
  }

  factory Textbook.fromJson(Map<String, dynamic> json) {
    final index = _maps(json['index']).map(TocUnit.fromJson).toList();
    final contents = _maps(json['contents']).map(ContentUnit.fromJson).toList();
    if (index.isEmpty || contents.isEmpty) {
      throw const FormatException('教材缺少 index 或 contents');
    }
    return Textbook(
      schemaVersion: _integer(json['schema_version']) ?? 1,
      index: index,
      contents: contents,
      highlights: HighlightIndex.fromJson(json),
    );
  }

  final int schemaVersion;
  final List<TocUnit> index;
  final List<ContentUnit> contents;
  final HighlightIndex highlights;
  final Map<String, ContentNode> chaptersById;
  final Map<String, ContentNode> nodesById;
  final Map<String, TextSegment> segmentsById;

  ContentNode? chapter(String id) => chaptersById[id];

  ContentNode? node(String id) => nodesById[id];

  TextSegment? segment(String id) => segmentsById[id];

  Iterable<ContentNode> get allNodes => nodesById.values;
}

Iterable<ContentNode> _collectNodes(ContentNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* _collectNodes(child);
  }
}

Map<String, ContentNode> _indexNodes(List<ContentUnit> contents) => {
  for (final root in contents.expand((unit) => unit.chapters))
    for (final node in _collectNodes(root)) node.id: node,
};

Map<String, TextSegment> _indexSegments(List<ContentUnit> contents) => {
  for (final root in contents.expand((unit) => unit.chapters))
    for (final node in _collectNodes(root))
      for (final segment in node.text)
        if (segment.id.isNotEmpty) segment.id: segment,
};

class TocUnit {
  const TocUnit({required this.id, required this.name, required this.chapters});

  factory TocUnit.fromJson(Map<String, dynamic> json) => TocUnit(
    id: _string(json['id']),
    name: _string(json['name']),
    chapters: _maps(json['chapters']).map(TocChapter.fromJson).toList(),
  );

  final String id;
  final String name;
  final List<TocChapter> chapters;
}

class TocChapter {
  const TocChapter({
    required this.id,
    required this.name,
    required this.no,
    required this.page,
    required this.children,
  });

  factory TocChapter.fromJson(Map<String, dynamic> json) => TocChapter(
    id: _string(json['id']),
    name: _string(json['name']),
    no: _integer(json['no']),
    page: _integer(json['page']),
    children: _maps(json['children']).map(TocChild.fromJson).toList(),
  );

  final String id;
  final String name;
  final int? no;
  final int? page;
  final List<TocChild> children;
}

class TocChild {
  const TocChild({required this.id, required this.name, required this.page});

  factory TocChild.fromJson(Map<String, dynamic> json) => TocChild(
    id: _string(json['id']),
    name: _string(json['name']),
    page: _integer(json['page']),
  );

  final String id;
  final String name;
  final int? page;
}

class ContentUnit {
  const ContentUnit({
    required this.id,
    required this.name,
    required this.chapters,
  });

  factory ContentUnit.fromJson(Map<String, dynamic> json) => ContentUnit(
    id: _string(json['id']),
    name: _string(json['name']),
    chapters: _maps(json['chapters']).map(ContentNode.fromJson).toList(),
  );

  final String id;
  final String name;
  final List<ContentNode> chapters;
}

class ContentNode {
  const ContentNode({
    required this.id,
    required this.name,
    required this.no,
    required this.page,
    required this.contentType,
    required this.memorize,
    required this.topic,
    required this.title,
    required this.author,
    required this.dynasty,
    required this.text,
    required this.children,
  });

  factory ContentNode.fromJson(Map<String, dynamic> json) => ContentNode(
    id: _string(json['id']),
    name: _string(json['name']),
    no: _integer(json['no']),
    page: _integer(json['page']),
    contentType: _string(json['content_type']),
    memorize: json['memorize'] == true,
    topic: BilingualText.fromValue(json['topic']),
    title: BilingualText.fromValue(json['title']),
    author: BilingualText.fromValue(json['author']),
    dynasty: BilingualText.fromValue(json['dynasty']),
    text: _maps(json['text']).map(TextSegment.fromJson).toList(),
    children: _maps(json['children']).map(ContentNode.fromJson).toList(),
  );

  final String id;
  final String name;
  final int? no;
  final int? page;
  final String contentType;
  final bool memorize;
  final BilingualText topic;
  final BilingualText title;
  final BilingualText author;
  final BilingualText dynasty;
  final List<TextSegment> text;
  final List<ContentNode> children;

  String get displayTitle => title.zh.isNotEmpty ? title.zh : name;
}

class BilingualText {
  const BilingualText({this.zh = '', this.pinyin = ''});

  factory BilingualText.fromValue(Object? value) {
    if (value is! Map<String, dynamic>) return const BilingualText();
    return BilingualText(
      zh: _string(value['zh']),
      pinyin: _string(value['pinyin']),
    );
  }

  final String zh;
  final String pinyin;

  bool get isEmpty => zh.isEmpty && pinyin.isEmpty;
}

class TextSegment extends BilingualText {
  const TextSegment({
    required this.id,
    required super.zh,
    required super.pinyin,
    required this.refs,
    required this.introducedChapterId,
  });

  factory TextSegment.fromJson(Map<String, dynamic> json) => TextSegment(
    id: _string(json['id']),
    zh: _string(json['zh']),
    pinyin: _string(json['pinyin']),
    refs: _maps(json['refs']).map(TextReference.fromJson).toList(),
    introducedChapterId: json['introduced_at'] is Map
        ? _string((json['introduced_at'] as Map)['chapter_id'])
        : '',
  );

  final String id;
  final List<TextReference> refs;
  final String introducedChapterId;
}

class TextReference {
  const TextReference({
    required this.unitId,
    required this.chapterId,
    required this.workId,
    required this.field,
    required this.segmentId,
  });

  factory TextReference.fromJson(Map<String, dynamic> json) => TextReference(
    unitId: _string(json['unit_id']),
    chapterId: _string(json['chapter_id']),
    workId: _string(json['work_id']),
    field: _string(json['field']),
    segmentId: _string(json['segment_id']),
  );

  final String unitId;
  final String chapterId;
  final String workId;
  final String field;
  final String segmentId;
}

class HighlightRange {
  const HighlightRange(this.start, this.length);

  final int start;
  final int length;

  int get end => start + length;

  bool contains(int index) => index >= start && index < end;
}

class HighlightIndex {
  HighlightIndex._(this._ranges);

  factory HighlightIndex.fromJson(Map<String, dynamic> json) {
    final ranges = <String, List<HighlightRange>>{};
    for (final unit in _maps(json['contents'])) {
      if (_string(unit['id']) != 'appendix') continue;
      for (final table in _maps(unit['chapters'])) {
        for (final entry in _maps(table['text'])) {
          _addRefs(ranges, _maps(entry['refs']));
        }
      }
    }
    return HighlightIndex._(_merge(ranges));
  }

  static void _addRefs(
    Map<String, List<HighlightRange>> ranges,
    List<Map<String, dynamic>> refs,
  ) {
    for (final ref in refs) {
      final segmentId = _string(ref['segment_id']);
      final workId = _string(ref['work_id']);
      final field = _string(ref['field']);
      final key = segmentId.isNotEmpty ? segmentId : '$workId#$field';
      if (key == '#') continue;
      final target = ranges.putIfAbsent(key, () => []);
      for (final match in _maps(ref['matches'])) {
        final start = _integer(match['start']);
        final length = _integer(match['length']);
        if (start != null && length != null && start >= 0 && length > 0) {
          target.add(HighlightRange(start, length));
        }
      }
    }
  }

  static Map<String, List<HighlightRange>> _merge(
    Map<String, List<HighlightRange>> source,
  ) {
    final result = <String, List<HighlightRange>>{};
    for (final entry in source.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) => a.start.compareTo(b.start));
      final merged = <HighlightRange>[];
      for (final range in sorted) {
        if (merged.isEmpty || range.start > merged.last.end) {
          merged.add(range);
        } else if (range.end > merged.last.end) {
          final previous = merged.removeLast();
          merged.add(
            HighlightRange(previous.start, range.end - previous.start),
          );
        }
      }
      result[entry.key] = merged;
    }
    return result;
  }

  final Map<String, List<HighlightRange>> _ranges;

  List<HighlightRange> forSegment(String id) => _ranges[id] ?? const [];

  List<HighlightRange> forField(String workId, String field) =>
      _ranges['$workId#$field'] ?? const [];
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList();
}

String _string(Object? value) => value is String ? value : '';

int? _integer(Object? value) => value is int ? value : null;
