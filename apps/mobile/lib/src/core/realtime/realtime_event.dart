class RealtimeEvent {
  const RealtimeEvent({
    required this.name,
    required this.payload,
    this.requestId,
    this.eventId,
    this.cursor,
    this.serverTime,
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return RealtimeEvent(
      name: json['event'] as String,
      requestId: json['requestId'] as String?,
      eventId: json['eventId'] as String?,
      cursor: json['eventCursor'] as String?,
      serverTime: json['serverTime'] == null
          ? null
          : DateTime.parse(json['serverTime'] as String).toLocal(),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }

  final String name;
  final String? requestId;
  final String? eventId;
  final String? cursor;
  final DateTime? serverTime;
  final Map<String, dynamic> payload;
}
