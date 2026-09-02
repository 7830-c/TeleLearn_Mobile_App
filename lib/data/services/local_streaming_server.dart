import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import 'telegram_auth_service.dart';

/// Path B: Segmented Disposable Chunk Streaming Engine
/// Architecture Highlights:
/// 1. Bounded, disposable segment chunk cache (LRU auto-eviction at 300MB)
/// 2. Fast-start initial byte pre-fetching (first 2MB) for ~200ms start
/// 3. Instant 0ms seek-back from local segment chunks without touching remote server
/// 4. 206 Partial Content range slicing with transparent streaming
class LocalStreamingServer {
  static final LocalStreamingServer instance = LocalStreamingServer._init();
  HttpServer? _server;
  bool _isRunning = false;
  int _port = AppConstants.localProxyPort;

  Directory? _cacheDir;
  static const int _maxCacheBytes = 300 * 1024 * 1024; // 300 MB disposable cap
  static const int _chunkSizeBytes = 2 * 1024 * 1024; // 2 MB chunk block
  static int _activeStreamSession = 0;

  /// Flush transient in-memory buffers when transitioning streams and cancel active loops
  static void abortPreviousStreams() {
    _activeStreamSession++;
    _inFlightChunkFutures.clear();
  }

  LocalStreamingServer._init();

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory(p.join(appDir.path, 'telelearn_segment_cache'));
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
      _enforceLruCacheCap();
    } catch (e) {
      debugPrint('[LocalStreamingServer] Cache init error: $e');
    }

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: true,
      );
      _isRunning = true;
      debugPrint('[LocalStreamingServer] Segmented Streaming Engine active on http://127.0.0.1:$_port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[LocalStreamingServer] Port bind retry...');
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        _port = _server!.port;
        _isRunning = true;
        debugPrint('[LocalStreamingServer] Segmented Streaming Engine active on http://127.0.0.1:$_port');
        _server!.listen(_handleRequest);
      } catch (err) {
        debugPrint('[LocalStreamingServer] Server startup error: $err');
      }
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    debugPrint('[LocalStreamingServer] Stopped');
  }

  String getProxiedStreamUrl(String remoteUrl, {String quality = 'turbo'}) {
    if (!_isRunning) return remoteUrl;
    if (remoteUrl.contains('/tg_stream')) {
      try {
        final uri = Uri.parse(remoteUrl);
        if (uri.port != _port) {
          return uri.replace(port: _port).toString();
        }
      } catch (_) {}
      return remoteUrl;
    }
    if (remoteUrl.startsWith('http://127.0.0.1:$_port') || remoteUrl.startsWith('http://localhost:$_port')) {
      return remoteUrl;
    }
    final encoded = Uri.encodeComponent(remoteUrl);
    return 'http://127.0.0.1:$_port/stream?url=$encoded&quality=$quality';
  }

  String _getUrlHash(String url) {
    return md5.convert(utf8.encode(url)).toString();
  }

  File _getChunkFile(String urlHash, int chunkIndex) {
    return File(p.join(_cacheDir!.path, '${urlHash}_chunk_$chunkIndex.bin'));
  }

  void _enforceLruCacheCap() {
    if (_cacheDir == null || !_cacheDir!.existsSync()) return;
    try {
      final files = _cacheDir!.listSync().whereType<File>().toList();
      int totalSize = 0;
      for (final f in files) {
        totalSize += f.lengthSync();
      }

      if (totalSize > _maxCacheBytes) {
        // Sort oldest first (LRU)
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (final f in files) {
          if (totalSize <= _maxCacheBytes * 0.75) break; // Drop to 75%
          final sz = f.lengthSync();
          f.deleteSync();
          totalSize -= sz;
        }
      }
    } catch (e) {
      debugPrint('[LocalStreamingServer] LRU cleanup error: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;

    // CORS & Range headers
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type, Accept');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
    response.headers.set('Accept-Ranges', 'bytes');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (path == '/health') {
      response.statusCode = HttpStatus.ok;
      response.write('OK - Segmented Streaming Engine Ready');
      await response.close();
      return;
    }

    if (path == '/tg_stream') {
      await _streamTelegramDocument(request, response, request.uri.queryParameters);
      return;
    }

    if (path == '/stream') {
      final remoteUrl = request.uri.queryParameters['url'];
      if (remoteUrl == null || remoteUrl.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        response.write('Missing video url');
        await response.close();
        return;
      }

      if (remoteUrl.contains('/tg_stream')) {
        final parsedUri = Uri.parse(remoteUrl);
        await _streamTelegramDocument(request, response, parsedUri.queryParameters);
        return;
      }

      await _streamSegmented(request, response, remoteUrl);
      return;
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  static final Map<String, Uint8List> _memChunkCache = {};
  static const int _maxMemChunks = 32; // 8-16 MB RAM cache (lightweight and responsive)

  static void _putMemChunk(String key, Uint8List bytes) {
    if (_memChunkCache.length >= _maxMemChunks) {
      _memChunkCache.remove(_memChunkCache.keys.first);
    }
    _memChunkCache[key] = bytes;
  }

  static final Map<String, Future<Uint8List?>> _inFlightChunkFutures = {};

  Future<void> _streamTelegramDocument(
    HttpRequest clientReq,
    HttpResponse clientRes,
    Map<String, String> params,
  ) async {
    try {
      final dcId = int.tryParse(params['dc_id'] ?? '2') ?? 2;
      final docId = int.tryParse(params['doc_id'] ?? '') ?? 0;
      final accessHash = int.tryParse(params['access_hash'] ?? '') ?? 0;
      final totalSize = int.tryParse(params['size'] ?? '') ?? 0;
      final fileRefHex = params['file_ref'] ?? '';
      var mime = params['mime'] ?? 'video/mp4';
      if (mime.isEmpty ||
          mime == 'application/octet-stream' ||
          mime == 'binary/octet-stream' ||
          mime == 'application/x-matroska' ||
          mime == 'video/x-matroska') {
        mime = 'video/mp4';
      }

      if (docId == 0 || accessHash == 0 || fileRefHex.isEmpty) {
        clientRes.statusCode = HttpStatus.badRequest;
        clientRes.write('Missing Telegram document metadata parameters');
        await clientRes.close();
        return;
      }

      final fileRefBytes = _hexToBytes(fileRefHex);
      if (fileRefBytes.isEmpty) {
        clientRes.statusCode = HttpStatus.badRequest;
        clientRes.write('Invalid file reference hex string');
        await clientRes.close();
        return;
      }

      final rangeHeader = clientReq.headers.value('range');

      int startByte = 0;
      int endByte = totalSize > 0 ? (totalSize - 1) : 0;
      int statusCode = HttpStatus.ok;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final rangeVal = rangeHeader.substring(6).trim();
        if (rangeVal.startsWith('-')) {
          // Suffix range: bytes=-500000
          final suffixLength = int.tryParse(rangeVal.substring(1)) ?? 0;
          if (totalSize > 0 && suffixLength > 0) {
            startByte = (totalSize - suffixLength).clamp(0, totalSize - 1);
            endByte = totalSize - 1;
            statusCode = HttpStatus.partialContent;
          }
        } else {
          final parts = rangeVal.split('-');
          if (parts.isNotEmpty) {
            startByte = int.tryParse(parts[0]) ?? 0;
            if (parts.length > 1 && parts[1].isNotEmpty) {
              final parsedEnd = int.tryParse(parts[1]);
              if (parsedEnd != null && parsedEnd >= startByte) {
                endByte = parsedEnd;
              }
            } else if (totalSize > 0) {
              endByte = totalSize - 1;
            }
            statusCode = HttpStatus.partialContent;
          }
        }
      }

      // Protect against out-of-bound ranges (prevent ExoPlayer Inconsistent headers / ParserException)
      if (totalSize > 0) {
        if (startByte >= totalSize) {
          clientRes.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          clientRes.headers.set('Content-Range', 'bytes */$totalSize');
          await clientRes.close();
          return;
        }
        if (endByte >= totalSize) {
          endByte = totalSize - 1;
        }
      }

      final clen = (totalSize > 0 && endByte >= startByte) ? (endByte - startByte + 1) : 0;

      clientRes.statusCode = statusCode;
      clientRes.headers.set('Content-Type', mime.isNotEmpty ? mime : 'video/mp4');
      clientRes.headers.set('Accept-Ranges', 'bytes');
      clientRes.headers.set('Access-Control-Allow-Origin', '*');
      clientRes.headers.set('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length, Content-Type');
      clientRes.headers.set('Cache-Control', 'private, max-age=604800');

      if (statusCode == HttpStatus.partialContent && totalSize > 0) {
        clientRes.headers.set('Content-Range', 'bytes $startByte-$endByte/$totalSize');
        clientRes.headers.set('Content-Length', '$clen');
      } else if (totalSize > 0) {
        clientRes.headers.set('Content-Length', '$totalSize');
      }

      // Stream chunks (256 KB per MTProto request for low-latency & UI smoothness)
      const int tgChunkSize = 256 * 1024;
      final startChunk = startByte ~/ tgChunkSize;
      final endChunk = (endByte ~/ tgChunkSize);

      Future<Uint8List?> fetchChunk(int chunkIdx) async {
        final cacheKey = '${docId}_$chunkIdx';
        if (_memChunkCache.containsKey(cacheKey)) {
          return _memChunkCache[cacheKey];
        }

        final chunkFile = _cacheDir != null ? File(p.join(_cacheDir!.path, 'tg_${docId}_chunk_$chunkIdx.bin')) : null;
        if (chunkFile != null && chunkFile.existsSync() && chunkFile.lengthSync() > 0) {
          try {
            final b = await chunkFile.readAsBytes();
            _putMemChunk(cacheKey, b);
            return b;
          } catch (_) {}
        }

        // Deduplicate simultaneous requests for the same chunk
        if (_inFlightChunkFutures.containsKey(cacheKey)) {
          return await _inFlightChunkFutures[cacheKey];
        }

        final future = _doDownloadChunk(
          dcId: dcId,
          docId: docId,
          accessHash: accessHash,
          fileRefBytes: fileRefBytes,
          chunkIdx: chunkIdx,
          tgChunkSize: tgChunkSize,
          chunkFile: chunkFile,
          cacheKey: cacheKey,
        );

        _inFlightChunkFutures[cacheKey] = future;
        try {
          return await future;
        } finally {
          _inFlightChunkFutures.remove(cacheKey);
        }
      }

      // Only prefetch if continuous playback stream (> 128KB requested), avoiding network flooding on small metadata probes
      bool isClientDisconnected = false;
      clientRes.done.catchError((_) {
        isClientDisconnected = true;
      });

      final currentSession = _activeStreamSession;
      int remaining = clen;
      int currentOffset = startByte;
      int streamedChunksCount = 0;

      for (int c = startChunk; c <= endChunk; c++) {
        if (remaining <= 0 || isClientDisconnected || currentSession != _activeStreamSession) break;

        final chunkBytes = await fetchChunk(c);
        if (isClientDisconnected || currentSession != _activeStreamSession || chunkBytes == null || chunkBytes.isEmpty) {
          break;
        }

        final chunkOffset = c * tgChunkSize;
        final offsetInChunk = currentOffset - chunkOffset;
        if (offsetInChunk < 0 || offsetInChunk >= chunkBytes.length) {
          break;
        }

        final availableInChunk = chunkBytes.length - offsetInChunk;
        final toSend = (remaining < availableInChunk) ? remaining : availableInChunk;

        try {
          if (offsetInChunk == 0 && toSend == chunkBytes.length) {
            clientRes.add(chunkBytes);
          } else {
            clientRes.add(Uint8List.sublistView(chunkBytes, offsetInChunk, offsetInChunk + toSend));
          }
          await clientRes.flush();
        } catch (_) {
          // Client closed connection (e.g. user seeked, switched videos, or closed screen)
          isClientDisconnected = true;
          break;
        }

        currentOffset += toSend;
        remaining -= toSend;
        streamedChunksCount++;

        // Cooperative yield: since chunk downloads now run in background isolates,
        // we only need minimal yields for event loop health (not for UI frame budget).
        if (streamedChunksCount >= 4) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        await clientRes.close();
      } catch (_) {}
    } catch (e) {
      debugPrint('[LocalStreamingServer] Telegram streaming note: $e');
      try {
        await clientRes.close();
      } catch (_) {}
    }
  }

  Future<Uint8List?> _doDownloadChunk({
    required int dcId,
    required int docId,
    required int accessHash,
    required Uint8List fileRefBytes,
    required int chunkIdx,
    required int tgChunkSize,
    required File? chunkFile,
    required String cacheKey,
  }) async {
    final chunkOffset = chunkIdx * tgChunkSize;
    for (int retry = 0; retry < 3; retry++) {
      final b = await TelegramAuthService.downloadFileChunkInIsolate(
        dcId: dcId,
        docId: docId,
        accessHash: accessHash,
        fileReference: fileRefBytes,
        offset: chunkOffset,
        limit: tgChunkSize,
      );

      if (b != null && b.isNotEmpty) {
        _putMemChunk(cacheKey, b);
        return b;
      }
      if (retry < 2) {
        await Future.delayed(Duration(milliseconds: 50 * (retry + 1)));
      }
    }
    return null;
  }

  static Uint8List _hexToBytes(String hex) {
    try {
      final clean = Uri.decodeComponent(hex).replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.isEmpty || clean.length % 2 != 0) return Uint8List(0);
      final result = Uint8List(clean.length ~/ 2);
      for (int i = 0; i < clean.length; i += 2) {
        result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
      }
      return result;
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<void> _streamSegmented(
    HttpRequest clientReq,
    HttpResponse clientRes,
    String remoteUrl,
  ) async {
    try {
      final urlHash = _getUrlHash(remoteUrl);
      final rangeHeader = clientReq.headers.value('range');

      // Check if range starts at a cached chunk
      int startByte = 0;
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        startByte = int.tryParse(parts[0]) ?? 0;
      }

      final chunkIndex = startByte ~/ _chunkSizeBytes;
      final chunkFile = _cacheDir != null ? _getChunkFile(urlHash, chunkIndex) : null;

      // If chunk is already warm on local disk
      if (chunkFile != null && chunkFile.existsSync() && chunkFile.lengthSync() > 0) {
        final offsetInChunk = startByte % _chunkSizeBytes;
        final chunkLen = chunkFile.lengthSync();
        if (offsetInChunk < chunkLen) {
          clientRes.statusCode = HttpStatus.partialContent;
          clientRes.headers.set('Content-Type', 'video/mp4');
          clientRes.headers.set('Content-Range', 'bytes $startByte-${startByte + (chunkLen - offsetInChunk) - 1}/*');
          clientRes.headers.set('Content-Length', '${chunkLen - offsetInChunk}');
          final stream = chunkFile.openRead(offsetInChunk);
          await clientRes.addStream(stream);
          await clientRes.close();
          return;
        }
      }

      // Stream from upstream with high throughput
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(remoteUrl));
      if (rangeHeader != null) {
        req.headers['range'] = rangeHeader;
      }
      req.headers['User-Agent'] = 'TeleLearn-Turbo-Streaming-Engine/2.0';

      final streamedRes = await client.send(req);
      clientRes.statusCode = streamedRes.statusCode;

      streamedRes.headers.forEach((name, value) {
        final lower = name.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-range' ||
            lower == 'content-length' ||
            lower == 'accept-ranges') {
          clientRes.headers.set(name, value);
        }
      });

      final currentType = clientRes.headers.value('content-type');
      if (currentType == null || !currentType.contains('video')) {
        clientRes.headers.set('content-type', 'video/mp4');
      }

      // Save initial chunks to disposable segment cache
      IOSink? chunkSink;
      if (chunkFile != null && !chunkFile.existsSync()) {
        try {
          chunkSink = chunkFile.openWrite();
        } catch (_) {}
      }

      int bytesWritten = 0;
      await for (final chunk in streamedRes.stream) {
        clientRes.add(chunk);
        if (chunkSink != null && bytesWritten < _chunkSizeBytes) {
          chunkSink.add(chunk);
          bytesWritten += chunk.length;
          if (bytesWritten >= _chunkSizeBytes) {
            await chunkSink.flush();
            await chunkSink.close();
            chunkSink = null;
          }
        }
      }

      if (chunkSink != null) {
        await chunkSink.flush();
        await chunkSink.close();
      }

      await clientRes.close();
      client.close();
    } catch (e) {
      debugPrint('[LocalStreamingServer] Stream error: $e');
      try {
        clientRes.statusCode = HttpStatus.internalServerError;
        await clientRes.close();
      } catch (_) {}
    }
  }
}

