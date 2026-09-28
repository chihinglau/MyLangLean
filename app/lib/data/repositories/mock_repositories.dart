import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/entities/episode.dart';
import '../../domain/entities/podcast.dart';
import '../../domain/entities/quota.dart';
import '../../domain/entities/recording.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/repositories/repositories.dart';
import '../mock/mock_catalog.dart';

class MockCatalogRepository implements CatalogRepository {
  @override
  Future<List<Podcast>> featured(
      {ContentLevel? level, String? language}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return MockCatalog.podcasts
        .where((p) => level == null || level == ContentLevel.all || p.level == level)
        .where((p) => language == null || language.isEmpty || p.language == language)
        .toList();
  }

  @override
  Future<List<Podcast>> search(String keyword) async {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return featured();
    return MockCatalog.podcasts
        .where((p) =>
            p.title.toLowerCase().contains(k) ||
            p.author.toLowerCase().contains(k) ||
            p.language.contains(k))
        .toList();
  }

  @override
  Future<List<Episode>> episodesOf(Podcast podcast) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return MockCatalog.episodesOf(podcast.id);
  }
}

class MockLibraryRepository implements LibraryRepository {
  final List<Podcast> _subscriptions = [];
  final List<Episode> _localMedia = [];

  @override
  List<Podcast> subscriptions() => List.unmodifiable(_subscriptions);

  @override
  Future<void> toggleSubscription(Podcast podcast) async {
    final exists = _subscriptions.any((p) => p.id == podcast.id);
    if (exists) {
      _subscriptions.removeWhere((p) => p.id == podcast.id);
    } else {
      _subscriptions.add(podcast);
    }
  }

  @override
  List<Episode> localMedia() => List.unmodifiable(_localMedia);

  @override
  Future<Episode> addLocalMedia(
    String mediaPath, {
    String? transcriptPath,
    String? title,
    String? language,
    int? durationMs,
  }) async {
    final name = title ?? mediaPath.split(RegExp(r'[\\/]')).last;
    final episode = Episode(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      title: name,
      audioUrl: mediaPath,
      duration: Duration(milliseconds: durationMs ?? 0),
      isLocal: true,
      localPath: mediaPath,
      transcriptPath: transcriptPath,
      language: language ?? 'en',
    );
    _localMedia.add(episode);
    return episode;
  }

  @override
  Future<Episode?> attachTranscript(
      String episodeId, String transcriptPath) async {
    final i = _localMedia.indexWhere((e) => e.id == episodeId);
    if (i < 0) return null;
    final updated = _localMedia[i].copyWith(transcriptPath: transcriptPath);
    _localMedia[i] = updated;
    return updated;
  }

  @override
  Future<void> removeLocalMedia(String episodeId) async {
    _localMedia.removeWhere((e) => e.id == episodeId);
  }
}

/// Resolves transcripts for playback:
///  * imported media with a sidecar file -> read that JSON from disk
///    (produced by the Windows Subtitle Studio, same schema v1)
///  * bundled sample episodes             -> assets/data/sample_transcript.json
///
/// Throws [TranscriptException] when a paired file is missing or malformed so
/// the UI can show a precise message instead of silently mismatching subtitles.
class LocalAwareTranscriptRepository implements TranscriptRepository {
  Transcript? _sampleCached;

  @override
  Future<Transcript?> transcriptFor(Episode episode) async {
    final sidecar = episode.transcriptPath;
    if (sidecar != null) {
      final file = File(sidecar);
      if (!await file.exists()) {
        throw TranscriptException('字幕文件不存在', sidecar);
      }
      try {
        final raw = await file.readAsString();
        return Transcript.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on FormatException catch (e) {
        throw TranscriptException('字幕文件格式错误：${e.message}', sidecar);
      }
    }
    // Bundled episodes (asset:// media) ship with the sample transcript;
    // arbitrary imported media without a sidecar simply has no subtitles.
    if (!episode.playableSource.startsWith('asset://')) return null;
    if (_sampleCached != null) return _sampleCached!;
    final raw =
        await rootBundle.loadString('assets/data/sample_transcript.json');
    _sampleCached =
        Transcript.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _sampleCached!;
  }
}

class TranscriptException implements Exception {
  TranscriptException(this.message, [this.path]);
  final String message;
  final String? path;

  @override
  String toString() =>
      path == null ? message : '$message（$path）';
}

class MockAuthRepository implements AuthRepository {
  Account _account = const Account(isGuest: true, deviceId: 'demo-device');
  UserQuota _quota = const UserQuota(usedSec: 1840, isGuest: true);

  @override
  Account current() => _account;

  @override
  UserQuota quota() => _quota;

  @override
  Future<Account> loginAsGuest() async {
    _account = const Account(isGuest: true, deviceId: 'demo-device');
    return _account;
  }

  @override
  Future<Account> login(
      {required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _account = Account(isGuest: false, name: email.split('@').first, email: email);
    _quota = _quota.copyWith(isGuest: false);
    return _account;
  }

  @override
  Future<void> logout() async {
    _account = const Account(isGuest: true, deviceId: 'demo-device');
    _quota = _quota.copyWith(isGuest: true);
  }
}

class MemoryPracticeRepository implements PracticeRepository {
  final List<Recording> _items = [];

  @override
  List<Recording> recordings() =>
      _items..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Recording> save(Recording recording) async {
    _items.removeWhere((r) => r.id == recording.id);
    _items.add(recording);
    return recording;
  }

  @override
  Future<void> delete(String id) async =>
      _items.removeWhere((r) => r.id == id);

  @override
  int totalPracticeSec() =>
      _items.fold(0, (sum, r) => sum + r.endMs - r.startMs) ~/ 1000;
}
