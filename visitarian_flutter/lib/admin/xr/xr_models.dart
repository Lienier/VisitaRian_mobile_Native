class XrHotspot {
  final String type;
  final double yaw;
  final double pitch;
  final String? title;
  final String? text;
  final String? toNodeId;
  final String? label;

  const XrHotspot({
    required this.type,
    required this.yaw,
    required this.pitch,
    this.title,
    this.text,
    this.toNodeId,
    this.label,
  });

  XrHotspot copyWith({
    String? type,
    double? yaw,
    double? pitch,
    String? title,
    String? text,
    String? toNodeId,
    String? label,
  }) {
    return XrHotspot(
      type: type ?? this.type,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      title: title ?? this.title,
      text: text ?? this.text,
      toNodeId: toNodeId ?? this.toNodeId,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'type': type, 'yaw': yaw, 'pitch': pitch};

    if (title != null && title!.trim().isNotEmpty) {
      map['title'] = title!.trim();
    }
    if (text != null && text!.trim().isNotEmpty) {
      map['text'] = text!.trim();
    }
    if (toNodeId != null && toNodeId!.trim().isNotEmpty) {
      map['toNodeId'] = toNodeId!.trim();
    }
    if (label != null && label!.trim().isNotEmpty) {
      map['label'] = label!.trim();
    }

    return map;
  }

  factory XrHotspot.fromMap(Map<String, dynamic> map) {
    return XrHotspot(
      type: (map['type'] ?? '').toString(),
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      title: map['title']?.toString(),
      text: map['text']?.toString(),
      toNodeId: map['toNodeId']?.toString(),
      label: map['label']?.toString(),
    );
  }
}

class XrNode {
  final String id;
  final String name;
  final String panoUrl;
  final List<XrHotspot> hotspots;

  const XrNode({
    required this.id,
    required this.name,
    required this.panoUrl,
    required this.hotspots,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'panoUrl': panoUrl,
      'hotspots': hotspots.map((e) => e.toMap()).toList(),
    };
  }

  factory XrNode.fromMap(String id, Map<String, dynamic> map) {
    final hotspotList = (map['hotspots'] as List<dynamic>? ?? const []);
    return XrNode(
      id: id,
      name: (map['name'] ?? '').toString(),
      panoUrl: (map['panoUrl'] ?? '').toString(),
      hotspots: hotspotList
          .whereType<Map<String, dynamic>>()
          .map(XrHotspot.fromMap)
          .toList(),
    );
  }
}
