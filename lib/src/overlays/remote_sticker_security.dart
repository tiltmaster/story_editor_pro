import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Supported remote sticker formats. SVG is intentionally excluded because
/// remote vector content has a much larger parser and resource-usage surface.
enum RemoteStickerImageFormat {
  png('png', <String>{'image/png', 'image/apng'}),
  jpeg('jpg', <String>{'image/jpeg', 'image/jpg'}),
  gif('gif', <String>{'image/gif'}),
  webp('webp', <String>{'image/webp'});

  const RemoteStickerImageFormat(this.extension, this.mimeTypes);

  final String extension;
  final Set<String> mimeTypes;
}

class RemoteStickerImageMetadata {
  const RemoteStickerImageMetadata({
    required this.width,
    required this.height,
    required this.frameCount,
  });

  final int width;
  final int height;
  final int frameCount;
}

class RemoteStickerPayload {
  const RemoteStickerPayload({
    required this.bytes,
    required this.format,
    required this.metadata,
  });

  final Uint8List bytes;
  final RemoteStickerImageFormat format;
  final RemoteStickerImageMetadata metadata;
}

/// Network and decode boundary for untrusted, host-provided sticker URLs.
class RemoteStickerSecurityPolicy {
  const RemoteStickerSecurityPolicy._();

  static const int maxDownloadBytes = 8 * 1024 * 1024;
  static const int maxThumbnailBytes = 2 * 1024 * 1024;
  static const int maxDimension = 4096;
  static const int maxPixels = 16 * 1024 * 1024;
  static const int maxFrameCount = 180;
  static const int maxAnimatedPixelWork = 64 * 1024 * 1024;

  static bool allowsUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) return false;

    // Reject literal private, loopback, link-local and unspecified addresses.
    final ipv4 = host.split('.').map(int.tryParse).toList();
    if (ipv4.length == 4 && ipv4.every((part) => part != null)) {
      final a = ipv4[0]!;
      final b = ipv4[1]!;
      if (a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          a >= 224) {
        return false;
      }
    }
    if (host == '::' ||
        host == '::1' ||
        host.startsWith('fc') ||
        host.startsWith('fd') ||
        host.startsWith('fe8') ||
        host.startsWith('fe9') ||
        host.startsWith('fea') ||
        host.startsWith('feb')) {
      return false;
    }
    return true;
  }

  static bool allowsAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      return !(a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          a >= 224);
    }
    if (bytes.length == 16) {
      // Only globally routable unicast IPv6 (2000::/3) is accepted.
      return (bytes[0] & 0xE0) == 0x20;
    }
    return false;
  }

  /// Requires every returned DNS address to be public and pins the request to
  /// the first validated address. Rejecting mixed answers avoids silently
  /// falling back to a private address.
  static InternetAddress requirePublicResolution(
    List<InternetAddress> addresses,
  ) {
    if (addresses.isEmpty ||
        addresses.any((address) => !allowsAddress(address))) {
      throw const FormatException('Remote sticker host is not public');
    }
    return addresses.first;
  }

  static void enforceSize(int byteCount, {int? limit}) {
    final resolvedLimit = limit ?? maxDownloadBytes;
    if (byteCount > resolvedLimit) {
      throw FormatException(
        'Remote sticker exceeds the ${resolvedLimit ~/ (1024 * 1024)} MB limit',
      );
    }
  }

  static void enforceImageBounds({
    required int width,
    required int height,
    required int frameCount,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width > maxDimension ||
        height > maxDimension ||
        width * height > maxPixels ||
        frameCount <= 0 ||
        frameCount > maxFrameCount ||
        width * height * frameCount > maxAnimatedPixelWork) {
      throw const FormatException('Remote sticker image is too complex');
    }
  }

  static RemoteStickerImageFormat detectFormat(Uint8List bytes) {
    bool matches(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature[index]) return false;
      }
      return true;
    }

    if (matches(const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return RemoteStickerImageFormat.png;
    }
    if (matches(const <int>[0xff, 0xd8, 0xff])) {
      return RemoteStickerImageFormat.jpeg;
    }
    if (matches(const <int>[0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        matches(const <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
      return RemoteStickerImageFormat.gif;
    }
    if (matches(const <int>[0x52, 0x49, 0x46, 0x46]) &&
        matches(const <int>[0x57, 0x45, 0x42, 0x50], 8)) {
      return RemoteStickerImageFormat.webp;
    }
    throw const FormatException('Unsupported remote sticker image format');
  }
}

Future<RemoteStickerImageMetadata> inspectRemoteStickerImage(
  Uint8List bytes,
) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    RemoteStickerSecurityPolicy.enforceImageBounds(
      width: width,
      height: height,
      frameCount: 1,
    );

    // Instantiate only a small target codec. This reveals animation frame
    // count without decoding an attacker-controlled full-resolution frame.
    final scale = width > height ? 256 / width : 256 / height;
    codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round().clamp(1, width),
      targetHeight: (height * scale).round().clamp(1, height),
    );
    final frameCount = codec.frameCount;
    RemoteStickerSecurityPolicy.enforceImageBounds(
      width: width,
      height: height,
      frameCount: frameCount,
    );
    return RemoteStickerImageMetadata(
      width: width,
      height: height,
      frameCount: frameCount,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Remote sticker image could not be decoded');
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<RemoteStickerPayload> fetchRemoteStickerPayload(
  String url, {
  int maxBytes = RemoteStickerSecurityPolicy.maxDownloadBytes,
}) async {
  if (!RemoteStickerSecurityPolicy.allowsUrl(url)) {
    throw const FormatException('Remote sticker URL is not allowed');
  }

  final uri = Uri.parse(url);
  final resolved = await InternetAddress.lookup(
    uri.host,
  ).timeout(const Duration(seconds: 5));
  final pinnedAddress = RemoteStickerSecurityPolicy.requirePublicResolution(
    resolved,
  );
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 8);
  client.findProxy = (_) => 'DIRECT';
  client.maxConnectionsPerHost = 1;

  // The validated DNS result is used for the actual socket, while TLS still
  // authenticates the original hostname. This closes the lookup/connect
  // rebinding window without weakening certificate or SNI validation.
  client.connectionFactory = (requestedUri, proxyHost, proxyPort) async {
    if (proxyHost != null ||
        proxyPort != null ||
        requestedUri.scheme.toLowerCase() != 'https' ||
        requestedUri.host.toLowerCase() != uri.host.toLowerCase() ||
        requestedUri.port != uri.port) {
      throw const FormatException('Remote sticker connection target changed');
    }
    final rawTask = await Socket.startConnect(pinnedAddress, requestedUri.port);
    Socket? connectedSocket;
    final Future<Socket> secureSocket = rawTask.socket.then<Socket>((
      socket,
    ) async {
      connectedSocket = socket;
      return SecureSocket.secure(socket, host: requestedUri.host);
    });
    return ConnectionTask.fromSocket<Socket>(secureSocket, () {
      rawTask.cancel();
      connectedSocket?.destroy();
    });
  };

  try {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('sticker download failed (${response.statusCode})');
    }

    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    const allowedContentTypes = <String>{
      'image/png',
      'image/apng',
      'image/jpeg',
      'image/jpg',
      'image/gif',
      'image/webp',
      'application/octet-stream',
    };
    if (contentType != null && !allowedContentTypes.contains(contentType)) {
      throw const FormatException(
        'Remote sticker response is not a safe image',
      );
    }

    final declaredLength = response.contentLength;
    if (declaredLength >= 0) {
      RemoteStickerSecurityPolicy.enforceSize(declaredLength, limit: maxBytes);
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      received += chunk.length;
      RemoteStickerSecurityPolicy.enforceSize(received, limit: maxBytes);
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final format = RemoteStickerSecurityPolicy.detectFormat(bytes);
    if (contentType != null &&
        contentType != 'application/octet-stream' &&
        !format.mimeTypes.contains(contentType)) {
      throw const FormatException(
        'Remote sticker type does not match its body',
      );
    }
    final metadata = await inspectRemoteStickerImage(bytes);
    return RemoteStickerPayload(
      bytes: bytes,
      format: format,
      metadata: metadata,
    );
  } finally {
    client.close(force: true);
  }
}
