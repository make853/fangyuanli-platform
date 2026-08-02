enum MediaPurpose {
  avatar('avatar'),
  background('background'),
  chat('chat'),
  post('post'),
  report('report'),
  placeClaim('placeClaim');

  const MediaPurpose(this.wireValue);

  final String wireValue;

  static MediaPurpose fromWire(String value) => values.firstWhere(
    (purpose) => purpose.wireValue == value,
    orElse: () => throw const FormatException('未知的媒体用途'),
  );
}

enum MediaUploadStatus {
  prepared,
  requestingTicket,
  uploading,
  confirming,
  processing,
  ready,
  paused,
  failed;

  bool get canResume =>
      this != MediaUploadStatus.ready && this != MediaUploadStatus.failed;
}

class PreparedImage {
  const PreparedImage({
    required this.localPath,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
  });

  final String localPath;
  final String fileName;
  final String contentType;
  final int bytes;
  final String sha256;
  final int width;
  final int height;
}

class MediaUploadTicket {
  const MediaUploadTicket({
    required this.uploadId,
    required this.method,
    required this.uploadUrl,
    required this.headers,
    required this.expiresAt,
  });

  final String uploadId;
  final String method;
  final Uri uploadUrl;
  final Map<String, String> headers;
  final DateTime expiresAt;

  bool isUsableAt(DateTime now) =>
      method == 'PUT' &&
      expiresAt.isAfter(now.add(const Duration(seconds: 15)));

  factory MediaUploadTicket.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    if (rawHeaders is! Map) {
      throw const FormatException('上传凭证缺少请求头');
    }
    return MediaUploadTicket(
      uploadId: json['uploadId'] as String,
      method: json['method'] as String,
      uploadUrl: Uri.parse(json['uploadUrl'] as String),
      headers: rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'uploadId': uploadId,
    'method': method,
    'uploadUrl': uploadUrl.toString(),
    'headers': headers,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

class MediaAsset {
  const MediaAsset({
    required this.mediaId,
    required this.status,
    this.mediaType,
    this.url,
    this.thumbnailUrl,
    this.coverUrl,
    this.width,
    this.height,
    this.durationMs,
    this.expiresAt,
  });

  final String mediaId;
  final String status;
  final String? mediaType;
  final Uri? url;
  final Uri? thumbnailUrl;
  final Uri? coverUrl;
  final int? width;
  final int? height;
  final int? durationMs;
  final DateTime? expiresAt;

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
    mediaId: json['mediaId'] as String,
    status: json['status'] as String,
    mediaType: json['mediaType'] as String?,
    url: _optionalUri(json['url']),
    thumbnailUrl: _optionalUri(json['thumbnailUrl']),
    coverUrl: _optionalUri(json['coverUrl']),
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationMs: json['durationMs'] as int?,
    expiresAt: _optionalDateTime(json['expiresAt']),
  );

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'status': status,
    if (mediaType != null) 'mediaType': mediaType,
    if (url != null) 'url': url.toString(),
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl.toString(),
    if (coverUrl != null) 'coverUrl': coverUrl.toString(),
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'durationMs': durationMs,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  static Uri? _optionalUri(Object? value) =>
      value is String && value.isNotEmpty ? Uri.parse(value) : null;

  static DateTime? _optionalDateTime(Object? value) =>
      value is String && value.isNotEmpty
      ? DateTime.parse(value).toUtc()
      : null;
}

class MediaUploadTask {
  const MediaUploadTask({
    required this.taskId,
    required this.ownerUserId,
    required this.purpose,
    required this.localPath,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
    required this.createIdempotencyKey,
    required this.completeIdempotencyKey,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.ticket,
    this.etag,
    this.mediaId,
    this.attempts = 0,
    this.errorMessage,
  });

  final String taskId;
  final String ownerUserId;
  final MediaPurpose purpose;
  final String localPath;
  final String fileName;
  final String contentType;
  final int bytes;
  final String sha256;
  final int width;
  final int height;
  final String createIdempotencyKey;
  final String completeIdempotencyKey;
  final MediaUploadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MediaUploadTicket? ticket;
  final String? etag;
  final String? mediaId;
  final int attempts;
  final String? errorMessage;

  factory MediaUploadTask.fromPrepared({
    required String taskId,
    required String ownerUserId,
    required MediaPurpose purpose,
    required PreparedImage image,
    required String createIdempotencyKey,
    required String completeIdempotencyKey,
    required DateTime now,
  }) => MediaUploadTask(
    taskId: taskId,
    ownerUserId: ownerUserId,
    purpose: purpose,
    localPath: image.localPath,
    fileName: image.fileName,
    contentType: image.contentType,
    bytes: image.bytes,
    sha256: image.sha256,
    width: image.width,
    height: image.height,
    createIdempotencyKey: createIdempotencyKey,
    completeIdempotencyKey: completeIdempotencyKey,
    status: MediaUploadStatus.prepared,
    createdAt: now,
    updatedAt: now,
  );

  MediaUploadTask copyWith({
    String? createIdempotencyKey,
    String? completeIdempotencyKey,
    MediaUploadStatus? status,
    DateTime? updatedAt,
    MediaUploadTicket? ticket,
    bool clearTicket = false,
    String? etag,
    bool clearEtag = false,
    String? mediaId,
    int? attempts,
    String? errorMessage,
    bool clearError = false,
  }) => MediaUploadTask(
    taskId: taskId,
    ownerUserId: ownerUserId,
    purpose: purpose,
    localPath: localPath,
    fileName: fileName,
    contentType: contentType,
    bytes: bytes,
    sha256: sha256,
    width: width,
    height: height,
    createIdempotencyKey: createIdempotencyKey ?? this.createIdempotencyKey,
    completeIdempotencyKey:
        completeIdempotencyKey ?? this.completeIdempotencyKey,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    ticket: clearTicket ? null : ticket ?? this.ticket,
    etag: clearEtag ? null : etag ?? this.etag,
    mediaId: mediaId ?? this.mediaId,
    attempts: attempts ?? this.attempts,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  factory MediaUploadTask.fromJson(Map<String, dynamic> json) {
    final ticket = json['ticket'];
    return MediaUploadTask(
      taskId: json['taskId'] as String,
      ownerUserId: json['ownerUserId'] as String,
      purpose: MediaPurpose.fromWire(json['purpose'] as String),
      localPath: json['localPath'] as String,
      fileName: json['fileName'] as String,
      contentType: json['contentType'] as String,
      bytes: json['bytes'] as int,
      sha256: json['sha256'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      createIdempotencyKey: json['createIdempotencyKey'] as String,
      completeIdempotencyKey: json['completeIdempotencyKey'] as String,
      status: MediaUploadStatus.values.byName(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      ticket: ticket is Map<String, dynamic>
          ? MediaUploadTicket.fromJson(ticket)
          : null,
      etag: json['etag'] as String?,
      mediaId: json['mediaId'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'ownerUserId': ownerUserId,
    'purpose': purpose.wireValue,
    'localPath': localPath,
    'fileName': fileName,
    'contentType': contentType,
    'bytes': bytes,
    'sha256': sha256,
    'width': width,
    'height': height,
    'createIdempotencyKey': createIdempotencyKey,
    'completeIdempotencyKey': completeIdempotencyKey,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'ticket': ticket?.toJson(),
    'etag': etag,
    'mediaId': mediaId,
    'attempts': attempts,
    'errorMessage': errorMessage,
  };
}

class MediaUploadOwnerMismatch implements Exception {
  const MediaUploadOwnerMismatch({
    required this.expectedOwnerUserId,
    required this.actualOwnerUserId,
  });

  final String expectedOwnerUserId;
  final String actualOwnerUserId;

  @override
  String toString() => '上传任务属于其他账号，请切换回原账号后继续';
}
