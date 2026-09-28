/**
 * MyLangLean - HarmonyOS audio playback plugin.
 *
 * Channel: ml/audio_player
 * Dart side: app/lib/pal/ohos/ohos_audio_player.dart
 *
 * Backed by @ohos.multimedia.media AVPlayer. Provides:
 *   load / play / pause / seek / setRate / setLoop(A-B) / dispose
 * and pushes onPosition / onState / onDuration events to Dart.
 *
 * Background playback & lock-screen controls use AVSession; the entry
 * ability must declare backgroundModes: ["audioPlayback"].
 */
import media from '@ohos.multimedia.media';
import avSession from '@ohos.multimedia.avsession';
import {
  AbilityAware,
  AbilityPluginBinding,
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import UIAbility from '@ohos.app.ability.UIAbility';

const TAG = 'MlAudioPlayer';
const CHANNEL = 'ml/audio_player';

export default class MlAudioPlayerPlugin
  implements MethodCallHandler, FlutterPlugin, AbilityAware {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private player: media.AVPlayer | null = null;
  private session: avSession.AVSession | null = null;
  private loopA: number = -1;
  private loopB: number = -1;
  private prepared: boolean = false;

  getUniqueClassName(): string {
    return 'MlAudioPlayerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case 'load':
          await this.load(call.argument('source') as string,
            call.argument('isLocal') as boolean);
          result.success(null);
          break;
        case 'play':
          await this.player?.play();
          result.success(null);
          break;
        case 'pause':
          await this.player?.pause();
          result.success(null);
          break;
        case 'seek':
          await this.player?.seek(call.argument('ms') as number,
            media.SeekMode.SEEK_CLOSEST);
          result.success(null);
          break;
        case 'setRate':
          await this.applyRate(call.argument('rate') as number);
          result.success(null);
          break;
        case 'setLoop': {
          const a: number | undefined = call.argument('a') as number | undefined;
          const b: number | undefined = call.argument('b') as number | undefined;
          this.loopA = (a === undefined || a === null) ? -1 : a as number;
          this.loopB = (b === undefined || b === null) ? -1 : b as number;
          result.success(null);
          break;
        }
        case 'dispose':
          await this.releasePlayer();
          result.success(null);
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      Log.e(TAG, 'onMethodCall error: ' + JSON.stringify(e));
      result.error('AUDIO_ERROR', `${call.method} failed`, JSON.stringify(e));
    }
  }

  private async load(source: string, isLocal: boolean): Promise<void> {
    await this.releasePlayer();
    this.prepared = false;
    this.player = await media.createAVPlayer();

    this.player.on('stateChange', async (state: string) => {
      Log.i(TAG, 'state=' + state);
      this.channel?.invokeMethod('onState', state === 'playing'
        ? 'playing'
        : (state === 'paused' ? 'paused' : state));
      if (state === 'initialized') {
        await this.player?.prepare();
      } else if (state === 'prepared') {
        this.prepared = true;
        await this.player?.play();
      }
    });

    // ~30Hz native position ticks drive the karaoke highlighter.
    this.player.on('timeUpdate', (timeMs: number) => {
      if (this.loopA >= 0 && this.loopB > this.loopA && timeMs >= this.loopB) {
        this.player?.seek(this.loopA, media.SeekMode.SEEK_CLOSEST);
        return;
      }
      this.channel?.invokeMethod('onPosition', timeMs);
    });

    this.player.on('durationUpdate', (durationMs: number) => {
      this.channel?.invokeMethod('onDuration', durationMs);
    });

    await this.ensureSession();
    if (isLocal) {
      // Local sandbox files are opened by fd in production; url is accepted
      // for fd:// and file:// style sources here as a fallback.
      this.player.url = source;
    } else {
      this.player.url = source;
    }
  }

  private async applyRate(rate: number): Promise<void> {
    if (!this.player) return;
    const map: Record<number, media.PlaybackSpeed> = {
      0.5: media.PlaybackSpeed.SPEED_FORWARD_0_50_X,
      0.75: media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
      1.0: media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
      1.25: media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
      1.5: media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
      2.0: media.PlaybackSpeed.SPEED_FORWARD_2_00_X,
    };
    // Nearest supported speed.
    const key = Object.keys(map)
      .map(Number)
      .reduce((a, b) => Math.abs(b - rate) < Math.abs(a - rate) ? b : a);
    await this.player.setSpeed(map[key]);
  }

  private async ensureSession(): Promise<void> {
    if (this.session || !this.ability) return;
    const ctx = this.ability.context;
    this.session = await avSession.createAVSession(ctx, 'mylanglean', 'audio');
    await this.session.activate();
    this.session.on('play', () => { this.player?.play(); });
    this.session.on('pause', () => { this.player?.pause(); });
    this.session.on('seek', (t: number) => {
      this.player?.seek(t, media.SeekMode.SEEK_CLOSEST);
    });
    Log.i(TAG, 'AVSession ready (audioPlayback declared in module.json5)');
  }

  private async releasePlayer(): Promise<void> {
    if (this.player) {
      try {
        await this.player.stop();
        await this.player.release();
      } catch (e) {
        Log.w(TAG, 'release: ' + JSON.stringify(e));
      }
      this.player = null;
    }
  }
}
