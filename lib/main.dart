import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart'
    show AudioPlayer, AssetSource, ReleaseMode, PlayerMode;
import 'package:vibration/vibration.dart' show Vibration;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameScreen(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

enum RaceState { countdown, racing, finished }

String formatTime(double s) {
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toStringAsFixed(2).padLeft(5, '0');
  return '$m:$sec';
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

// ---------------------------------------------------------------------------
// Áudio
// ---------------------------------------------------------------------------

class GameAudio {
  final AudioPlayer _engine = AudioPlayer();
  final AudioPlayer _skid = AudioPlayer();
  final AudioPlayer _crash = AudioPlayer();
  final AudioPlayer _beep = AudioPlayer();

  bool muted = false;
  bool _ready = false;
  bool _loopsPlaying = false;
  bool _suspended = false;
  double _timer = 0.0;
  double _crashCooldown = 0.0;
  double _lastRate = -1;
  double _lastEngineVol = -1;
  double _lastSkidVol = -1;

  void _safe(Future<void> f) {
    f.catchError((_) {});
  }

  Future<void> init() async {
    try {
      await _engine.setReleaseMode(ReleaseMode.loop);
      await _skid.setReleaseMode(ReleaseMode.loop);
      await _crash.setPlayerMode(PlayerMode.lowLatency);
      await _beep.setPlayerMode(PlayerMode.lowLatency);
      _ready = true;
    } catch (e) {
      debugPrint('Áudio indisponível: $e');
    }
  }

  void startLoops() {
    if (!_ready || _loopsPlaying) return;
    _loopsPlaying = true;
    _safe(_engine.play(AssetSource('audio/engine.wav'), volume: 0.2));
    _safe(_skid.play(AssetSource('audio/skid.wav'), volume: 0.0));
  }

  /// Chamado a cada frame; só fala com o plugin a cada ~60 ms e quando
  /// algum valor mudou de forma perceptível.
  void update(
    double dt, {
    required double speed,
    required double maxSpeed,
    required double throttle,
    required bool braking,
    required double slip,
    required bool engineOn,
  }) {
    _crashCooldown -= dt;
    if (!_ready || _suspended) return;
    _timer += dt;
    if (_timer < 0.06) return;
    _timer = 0.0;

    final frac = _clamp01(speed / maxSpeed);

    // Motor: a rotação (playbackRate) acompanha a velocidade.
    final rate = 0.8 + 1.1 * frac + (throttle > 0 ? 0.08 : 0.0);
    var engVol = engineOn
        ? 0.25 + 0.5 * frac + (throttle > 0 ? 0.15 : 0.0)
        : 0.0;

    // Freada / derrapagem: chiado de pneu.
    var skidVol = 0.0;
    if (slip > 35 && speed > 60) skidVol = _clamp01((slip - 35) / 110);
    if (braking && speed > 90) skidVol = max(skidVol, 0.55 * frac);

    if (muted) {
      engVol = 0.0;
      skidVol = 0.0;
    }

    if ((rate - _lastRate).abs() > 0.02) {
      _lastRate = rate;
      _safe(_engine.setPlaybackRate(rate));
    }
    if ((engVol - _lastEngineVol).abs() > 0.02) {
      _lastEngineVol = engVol;
      _safe(_engine.setVolume(_clamp01(engVol)));
    }
    if ((skidVol - _lastSkidVol).abs() > 0.02) {
      _lastSkidVol = skidVol;
      _safe(_skid.setVolume(_clamp01(skidVol)));
    }
  }

  Future<void> _playOnce(AudioPlayer p, String file, double vol) async {
    try {
      await p.stop();
      await p.play(AssetSource(file), volume: _clamp01(vol));
    } catch (_) {}
  }

  void crash(double intensity) {
    if (!_ready || muted || _suspended || _crashCooldown > 0) return;
    _crashCooldown = 0.2;
    _playOnce(_crash, 'audio/crash.wav', 0.4 + 0.6 * intensity);
  }

  void beep({required bool go}) {
    if (!_ready || muted || _suspended) return;
    _playOnce(_beep, go ? 'audio/go.wav' : 'audio/beep.wav', 0.8);
  }

  void suspend() {
    _suspended = true;
    _safe(_engine.pause());
    _safe(_skid.pause());
  }

  void resume() {
    _suspended = false;
    if (_loopsPlaying) {
      _safe(_engine.resume());
      _safe(_skid.resume());
    }
  }

  void dispose() {
    _safe(_engine.dispose());
    _safe(_skid.dispose());
    _safe(_crash.dispose());
    _safe(_beep.dispose());
  }
}

// ---------------------------------------------------------------------------
// Vibração
// ---------------------------------------------------------------------------

class Haptics {
  bool _hasVibrator = false;
  bool _hasAmplitude = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    try {
      _hasVibrator = (await Vibration.hasVibrator()) == true;
      _hasAmplitude = (await Vibration.hasAmplitudeControl()) == true;
    } catch (_) {
      _hasVibrator = false;
    }
  }

  /// [intensity] de 0 a 1: batidas fortes vibram mais forte e por mais tempo.
  void hit(double intensity) {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 180) return;
    _last = now;

    if (_hasVibrator) {
      final ms = (30 + 120 * intensity).round();
      final amp = (80 + 175 * intensity).round().clamp(1, 255);
      try {
        if (_hasAmplitude) {
          Vibration.vibrate(duration: ms, amplitude: amp);
        } else {
          Vibration.vibrate(duration: ms);
        }
        return;
      } catch (_) {}
    }
    HapticFeedback.heavyImpact(); // plano B (ex.: iOS)
  }
}

// ---------------------------------------------------------------------------
// Tela + HUD
// ---------------------------------------------------------------------------

class GameScreen extends StatefulWidget {
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final RacingGame game;

  @override
  void initState() {
    super.initState();
    game = RacingGame();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      game.audio.resume();
    } else {
      game.audio.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    game.audio.dispose();
    super.dispose();
  }

  Widget _panel({required Widget child, Color border = Colors.white24}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GameWidget(game: game),
        SafeArea(
          child: Stack(
            children: [
              // HUD superior esquerdo: volta, tempo, melhor volta
              Positioned(
                top: 12,
                left: 20,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    game.lapNotifier,
                    game.lapTimeNotifier,
                    game.bestLapNotifier,
                  ]),
                  builder: (context, _) {
                    final best = game.bestLapNotifier.value;
                    return _panel(
                      child: Text(
                        'VOLTA ${game.lapNotifier.value}/${RacingGame.totalLaps}\n'
                        'TEMPO  ${formatTime(game.lapTimeNotifier.value)}\n'
                        'MELHOR ${best == null ? '--:--.--' : formatTime(best)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Velocímetro (direita)
              Positioned(
                top: 12,
                right: 20,
                child: ValueListenableBuilder<double>(
                  valueListenable: game.speedNotifier,
                  builder: (context, speed, child) {
                    return _panel(
                      border: Colors.orangeAccent,
                      child: SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${speed.abs().toStringAsFixed(0)} KM/H',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _clamp01(speed.abs() / 260),
                                minHeight: 6,
                                backgroundColor: Colors.white12,
                                color: speed.abs() > 220
                                    ? Colors.redAccent
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Botão de som
              Positioned(
                top: 80,
                right: 20,
                child: ValueListenableBuilder<bool>(
                  valueListenable: game.mutedNotifier,
                  builder: (context, muted, _) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                        ),
                        onPressed: game.toggleMute,
                      ),
                    );
                  },
                ),
              ),

              // Mensagem central (contagem regressiva / VAI!)
              Center(
                child: ValueListenableBuilder<String?>(
                  valueListenable: game.messageNotifier,
                  builder: (context, msg, _) {
                    if (msg == null) return const SizedBox.shrink();
                    return Text(
                      msg,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                      ),
                    );
                  },
                ),
              ),

              // Botões táteis (esquerda)
              Positioned(
                bottom: 20,
                left: 25,
                child: Row(
                  children: [
                    _buildBtn(Icons.arrow_back, () => game.screenSteering = -1.0,
                        () => game.screenSteering = 0.0),
                    const SizedBox(width: 15),
                    _buildBtn(Icons.arrow_forward,
                        () => game.screenSteering = 1.0,
                        () => game.screenSteering = 0.0),
                  ],
                ),
              ),

              // Pedais táteis (direita)
              Positioned(
                bottom: 20,
                right: 25,
                child: Row(
                  children: [
                    _buildBtn(Icons.pan_tool, () => game.screenHandbrake = true,
                        () => game.screenHandbrake = false,
                        color: const Color(0xCCFFB300)),
                    const SizedBox(width: 15),
                    _buildBtn(Icons.arrow_downward,
                        () => game.screenThrottle = -1.0,
                        () => game.screenThrottle = 0.0,
                        color: const Color(0xCCFF5252)),
                    const SizedBox(width: 15),
                    _buildBtn(Icons.arrow_upward,
                        () => game.screenThrottle = 1.0,
                        () => game.screenThrottle = 0.0,
                        color: const Color(0xCC69F0AE)),
                  ],
                ),
              ),

              // Painel de fim de corrida
              Center(
                child: ValueListenableBuilder<RaceState>(
                  valueListenable: game.stateNotifier,
                  builder: (context, state, _) {
                    if (state != RaceState.finished) {
                      return const SizedBox.shrink();
                    }
                    final best = game.bestLapNotifier.value;
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orangeAccent, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'BANDEIRADA!',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tempo total: ${formatTime(game.totalTimeNotifier.value)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                          ),
                          Text(
                            'Melhor volta: ${best == null ? '--' : formatTime(best)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: game.restart,
                            child: const Text('JOGAR NOVAMENTE'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Listener (em vez de GestureDetector) permite multitoque confiável:
  // virar e acelerar ao mesmo tempo.
  Widget _buildBtn(IconData icon, VoidCallback onDown, VoidCallback onUp,
      {Color color = Colors.white24}) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jogo
// ---------------------------------------------------------------------------

class RacingGame extends FlameGame with KeyboardEvents {
  static const int totalLaps = 3;

  late CarComponent playerCar;
  late TrackComponent track;

  final GameAudio audio = GameAudio();
  final Haptics haptics = Haptics();
  final ValueNotifier<bool> mutedNotifier = ValueNotifier<bool>(false);

  double screenSteering = 0.0;
  double screenThrottle = 0.0;
  bool screenHandbrake = false;
  final Set<LogicalKeyboardKey> _keysPressed = {};

  // Notificadores usados pelo HUD
  final ValueNotifier<double> speedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> lapNotifier = ValueNotifier<int>(1);
  final ValueNotifier<double> lapTimeNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> totalTimeNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double?> bestLapNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<RaceState> stateNotifier =
      ValueNotifier<RaceState>(RaceState.countdown);
  final ValueNotifier<String?> messageNotifier = ValueNotifier<String?>('3');

  // Estado da corrida
  double _countdown = 3.0;
  double _messageTimer = 0.0;
  double _lapTime = 0.0;
  double _totalTime = 0.0;
  int _lapsDone = 0;
  double _totalProgress = 0.0; // 1.0 = uma volta completa
  double? _lastP;
  bool _pendingRestart = true;
  int _lastCount = 4;

  @override
  Color backgroundColor() => const Color(0xFF2E7D32); // Relva circundante

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await audio.init();
    await haptics.init();

    track = TrackComponent();
    add(track);

    playerCar = CarComponent();
    add(playerCar);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      track.updateDimensions(size);
      // Não mexemos nos notifiers aqui (estamos na fase de layout).
      _pendingRestart = true;
    }
  }

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _keysPressed.clear();
    _keysPressed.addAll(keysPressed);
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyR ||
          event.logicalKey == LogicalKeyboardKey.gameButtonStart) {
        restart();
      } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
        toggleMute();
      }
    }
    return KeyEventResult.handled;
  }

  void toggleMute() {
    audio.muted = !audio.muted;
    mutedNotifier.value = audio.muted;
  }

  /// Chamado pelo carro quando bate no guard-rail.
  /// [impact] = velocidade (px/s) na direção da parede.
  void onWallHit(double impact) {
    if (impact < 40) return; // roçar de leve não conta
    final k = _clamp01(impact / 220);
    audio.crash(k);
    haptics.hit(k);
  }

  void restart() {
    _countdown = 3.0;
    _messageTimer = 0.0;
    _lapTime = 0.0;
    _totalTime = 0.0;
    _lapsDone = 0;
    _totalProgress = 0.0;
    _lastP = null;
    _lastCount = 4;

    track.skidMarks.clear();
    playerCar.resetPositionOnTrack();

    lapNotifier.value = 1;
    lapTimeNotifier.value = 0.0;
    totalTimeNotifier.value = 0.0;
    stateNotifier.value = RaceState.countdown;
    messageNotifier.value = '3';
    _updateProgress();
  }

  @override
  void update(double dt) {
    dt = min(dt, 0.05); // evita saltos de física em quedas de FPS

    double kbSteer = 0.0;
    double kbThrottle = 0.0;

    if (_keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _keysPressed.contains(LogicalKeyboardKey.keyA)) {
      kbSteer -= 1.0;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        _keysPressed.contains(LogicalKeyboardKey.keyD)) {
      kbSteer += 1.0;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        _keysPressed.contains(LogicalKeyboardKey.keyW) ||
        _keysPressed.contains(LogicalKeyboardKey.gameButtonA) ||
        _keysPressed.contains(LogicalKeyboardKey.gameButtonRight2)) {
      kbThrottle += 1.0;
    }
    if (_keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        _keysPressed.contains(LogicalKeyboardKey.keyS) ||
        _keysPressed.contains(LogicalKeyboardKey.gameButtonB) ||
        _keysPressed.contains(LogicalKeyboardKey.gameButtonLeft2)) {
      kbThrottle -= 1.0;
    }

    final steerVal = (screenSteering != 0) ? screenSteering : kbSteer;
    final throttleVal = (screenThrottle != 0) ? screenThrottle : kbThrottle;
    final racing = stateNotifier.value == RaceState.racing;

    // Durante a contagem regressiva o carro fica parado.
    playerCar.steerInput = racing ? steerVal : 0.0;
    playerCar.throttleInput = racing ? throttleVal : 0.0;
    playerCar.handbrake = racing &&
        (screenHandbrake ||
            _keysPressed.contains(LogicalKeyboardKey.space) ||
            _keysPressed.contains(LogicalKeyboardKey.gameButtonX));

    super.update(dt);

    if (!track.ready) return;
    if (_pendingRestart) {
      _pendingRestart = false;
      restart();
      return;
    }

    _tickRace(dt);
    speedNotifier.value = playerCar.currentSpeed;

    audio.startLoops();
    audio.update(
      dt,
      speed: playerCar.currentSpeed,
      maxSpeed: playerCar.maxSpeed,
      throttle: playerCar.throttleInput,
      braking: playerCar.braking,
      slip: playerCar.slip,
      engineOn: stateNotifier.value != RaceState.finished,
    );
  }

  void _tickRace(double dt) {
    final state = stateNotifier.value;

    if (state == RaceState.countdown) {
      _countdown -= dt;
      if (_countdown <= 0) {
        stateNotifier.value = RaceState.racing;
        messageNotifier.value = 'VAI!';
        _messageTimer = 0.9;
        audio.beep(go: true);
      } else {
        final c = _countdown.ceil();
        if (c != _lastCount) {
          _lastCount = c;
          audio.beep(go: false);
        }
        messageNotifier.value = c.toString();
      }
      return;
    }

    if (_messageTimer > 0) {
      _messageTimer -= dt;
      if (_messageTimer <= 0) messageNotifier.value = null;
    }

    if (state == RaceState.racing) {
      _lapTime += dt;
      _totalTime += dt;
      lapTimeNotifier.value = _lapTime;
      _updateProgress();
    }
  }

  /// Progresso baseado no ângulo em relação ao centro da pista.
  /// Só conta voltas completas no sentido certo (não dá para "roubar"
  /// dando ré sobre a linha de chegada).
  void _updateProgress() {
    final c = track.trackRect.center;
    final a = atan2(
      playerCar.position.y - c.dy,
      playerCar.position.x - c.dx,
    );
    var p = (a - pi / 2) / (2 * pi);
    p -= p.roundToDouble(); // [-0.5, 0.5]

    if (_lastP == null) {
      _totalProgress = p;
    } else {
      var d = p - _lastP!;
      if (d > 0.5) d -= 1.0;
      if (d < -0.5) d += 1.0;
      _totalProgress += d;
    }
    _lastP = p;

    while (stateNotifier.value == RaceState.racing &&
        _totalProgress >= _lapsDone + 1) {
      _completeLap();
    }
  }

  void _completeLap() {
    _lapsDone++;
    final best = bestLapNotifier.value;
    if (best == null || _lapTime < best) {
      bestLapNotifier.value = _lapTime;
    }
    _lapTime = 0.0;
    lapTimeNotifier.value = 0.0;

    if (_lapsDone >= totalLaps) {
      totalTimeNotifier.value = _totalTime;
      stateNotifier.value = RaceState.finished;
    } else {
      lapNotifier.value = _lapsDone + 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Pista
// ---------------------------------------------------------------------------

class TrackComponent extends PositionComponent with HasGameRef<RacingGame> {
  // Parâmetros da geometria do circuito
  double trackMargin = 80.0;
  double trackRadius = 90.0;
  double trackWidth = 100.0; // Largura do asfalto

  bool ready = false;
  late Rect trackRect;
  late RRect trackRRect;
  late double effectiveRadius;

  late Path _trackPath;
  late Path _curbDashes;
  late Path _centerDashes;
  late RRect _innerRRect;

  final List<Offset> skidMarks = [];

  late final Paint _grassPaint = Paint()..color = const Color(0x14000000);
  late final Paint _outerRailPaint = Paint()
    ..color = const Color(0xFFB0BEC5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = trackWidth + 24;
  late final Paint _curbRedPaint = Paint()
    ..color = const Color(0xFFD32F2F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = trackWidth + 14;
  late final Paint _curbWhitePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = trackWidth + 14;
  late final Paint _asphaltPaint = Paint()
    ..color = const Color(0xFF263238)
    ..style = PaintingStyle.stroke
    ..strokeWidth = trackWidth;
  late final Paint _linePaint = Paint()
    ..color = Colors.white70
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _innerRailPaint = Paint()
    ..color = const Color(0xFF78909C)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6;
  final Paint _skidPaint = Paint()..color = const Color(0x55000000);
  final Paint _whitePaint = Paint()..color = Colors.white;
  final Paint _blackPaint = Paint()..color = Colors.black87;

  void updateDimensions(Vector2 size) {
    final w = size.x;
    final h = size.y;
    // Asfalto proporcional à altura da tela (celular na horizontal é baixo)
    trackWidth = (h * 0.2).clamp(60.0, 100.0).toDouble();
    _outerRailPaint.strokeWidth = trackWidth + 24;
    _curbRedPaint.strokeWidth = trackWidth + 14;
    _curbWhitePaint.strokeWidth = trackWidth + 14;
    _asphaltPaint.strokeWidth = trackWidth;
    final vMargin = trackWidth / 2 + 24;
    trackRect = Rect.fromLTWH(
      trackMargin,
      vMargin,
      w - (trackMargin * 2),
      h - (vMargin * 2),
    );
    effectiveRadius = max(
      1.0,
      min(trackRadius, min(trackRect.width, trackRect.height) / 2 - 1),
    );
    trackRRect =
        RRect.fromRectAndRadius(trackRect, Radius.circular(effectiveRadius));

    _trackPath = Path()..addRRect(trackRRect);
    _curbDashes = _dash(_trackPath, 16, 16);
    _centerDashes = _dash(_trackPath, 18, 14);
    _innerRRect = RRect.fromRectAndRadius(
      trackRect.deflate(trackWidth / 2 + 3),
      Radius.circular(max(0.0, effectiveRadius - trackWidth / 2 - 3)),
    );
    ready = true;
  }

  Path _dash(Path src, double dash, double gap) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, min(d + dash, m.length)), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  /// Distância assinada do ponto ao eixo central da pista
  /// (positivo = lado de fora, negativo = lado de dentro).
  /// [outNormal] recebe a normal (direção em que a distância cresce).
  double signedDistance(Vector2 p, Vector2 outNormal) {
    final c = trackRect.center;
    final dx = p.x - c.dx;
    final dy = p.y - c.dy;
    final hx = trackRect.width / 2;
    final hy = trackRect.height / 2;
    final r = effectiveRadius;

    final qx = dx.abs() - (hx - r);
    final qy = dy.abs() - (hy - r);
    final sx = dx < 0 ? -1.0 : 1.0;
    final sy = dy < 0 ? -1.0 : 1.0;

    final ox = max(qx, 0.0);
    final oy = max(qy, 0.0);
    final outside = sqrt(ox * ox + oy * oy);

    double nx, ny;
    if (outside > 0) {
      nx = ox / outside;
      ny = oy / outside;
    } else if (qx > qy) {
      nx = 1.0;
      ny = 0.0;
    } else {
      nx = 0.0;
      ny = 1.0;
    }
    outNormal.setValues(nx * sx, ny * sy);
    return outside + min(max(qx, qy), 0.0) - r;
  }

  void addSkid(Offset o) {
    skidMarks.add(o);
    if (skidMarks.length > 900) skidMarks.removeRange(0, 2);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    updateDimensions(gameRef.size);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!ready) return;

    // Listras do gramado
    final sz = gameRef.size;
    const stripe = 48.0;
    for (double x = 0, i = 0; x < sz.x; x += stripe, i++) {
      if (i.toInt().isOdd) {
        canvas.drawRect(Rect.fromLTWH(x, 0, stripe, sz.y), _grassPaint);
      }
    }

    // Guard-rail exterior
    canvas.drawPath(_trackPath, _outerRailPaint);

    // Zebras vermelho/branco
    canvas.drawPath(_trackPath, _curbRedPaint);
    canvas.drawPath(_curbDashes, _curbWhitePaint);

    // Asfalto
    canvas.drawPath(_trackPath, _asphaltPaint);

    // Marcas de pneu
    for (final o in skidMarks) {
      canvas.drawCircle(o, 1.6, _skidPaint);
    }

    // Linha de centro tracejada
    canvas.drawPath(_centerDashes, _linePaint);

    // Guard-rail interior
    canvas.drawRRect(_innerRRect, _innerRailPaint);

    // Linha de chegada quadriculada
    const cols = 2;
    const rows = 8;
    const cw = 12.0;
    final ch = trackWidth / rows;
    final x0 = trackRect.center.dx - cw * cols / 2;
    final y0 = trackRect.bottom - trackWidth / 2;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(x0 + c * cw, y0 + r * ch, cw, ch),
          (r + c).isEven ? _whitePaint : _blackPaint,
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Carro
// ---------------------------------------------------------------------------

class CarComponent extends PositionComponent with HasGameRef<RacingGame> {
  final Vector2 velocity = Vector2.zero();
  double currentSpeed = 0.0;

  // Entradas (preenchidas pelo jogo a cada frame)
  double throttleInput = 0.0;
  double steerInput = 0.0;
  bool handbrake = false;

  final double maxSpeed = 260.0;
  final double accelerationRate = 220.0;
  final double brakeRate = 420.0;
  final double turnSpeed = 3.4;
  final double drag = 0.85; // arrasto do ar/rolamento (por segundo)
  final double gripNormal = 6.5; // aderência lateral
  final double gripHandbrake = 1.6; // com freio de mão o carro derrapa

  bool braking = false;
  double slip = 0.0;
  final Vector2 _normal = Vector2.zero();

  CarComponent()
      : super(
          size: Vector2(26, 48),
          anchor: Anchor.center,
        );

  void resetPositionOnTrack() {
    final track = gameRef.track;
    final r = track.effectiveRadius;
    final straightHalf = max(0.0, track.trackRect.width / 2 - r);
    final offset = min(60.0, straightHalf);
    // Grid de largada: um pouco antes da linha de chegada, virado para a esquerda
    position = Vector2(
      track.trackRect.center.dx + offset,
      track.trackRect.bottom,
    );
    angle = -pi / 2;
    velocity.setZero();
    currentSpeed = 0.0;
    throttleInput = 0.0;
    steerInput = 0.0;
    handbrake = false;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Rodas
    final tirePaint = Paint()..color = Colors.black;
    canvas.drawRect(const Rect.fromLTWH(-3, 4, 5, 11), tirePaint);
    canvas.drawRect(Rect.fromLTWH(size.x - 2, 4, 5, 11), tirePaint);
    canvas.drawRect(const Rect.fromLTWH(-3, 31, 5, 11), tirePaint);
    canvas.drawRect(Rect.fromLTWH(size.x - 2, 31, 5, 11), tirePaint);

    // Chassi desportivo
    final bodyPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(6)),
      bodyPaint,
    );

    // Faixa desportiva central branca
    final stripePaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(size.x / 2 - 2, 0, 4, size.y), stripePaint);

    // Vidros dianteiro e traseiro
    final glassPaint = Paint()..color = const Color(0xFF4FC3F7);
    canvas.drawRect(Rect.fromLTWH(4, 11, size.x - 8, 8), glassPaint);
    canvas.drawRect(Rect.fromLTWH(5, 29, size.x - 10, 5), glassPaint);

    // Faróis dianteiros
    final lightPaint = Paint()..color = Colors.amberAccent;
    canvas.drawCircle(const Offset(5, 3), 2.5, lightPaint);
    canvas.drawCircle(Offset(size.x - 5, 3), 2.5, lightPaint);

    // Luzes de freio (acendem ao frear)
    final tailPaint = Paint()
      ..color = braking ? const Color(0xFFFF1744) : const Color(0xFF7F0000);
    canvas.drawRect(Rect.fromLTWH(3, size.y - 4, 7, 3), tailPaint);
    canvas.drawRect(Rect.fromLTWH(size.x - 10, size.y - 4, 7, 3), tailPaint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final track = gameRef.track;
    if (!track.ready) return;

    // 1) Direção: a esterçada depende da velocidade para frente.
    var fwd = Vector2(sin(angle), -cos(angle));
    final f0 = velocity.dot(fwd);
    final dir = f0 >= 0 ? 1.0 : -1.0;
    var steerFactor = _clamp01(f0.abs() / 70) *
        (1 - 0.25 * _clamp01(f0.abs() / maxSpeed));
    if (handbrake) steerFactor *= 1.25;
    angle += steerInput * turnSpeed * steerFactor * dir * dt;

    // 2) Decompõe a velocidade nos eixos do carro (frente / lateral).
    fwd = Vector2(sin(angle), -cos(angle));
    final right = Vector2(cos(angle), sin(angle));
    var f = velocity.dot(fwd);
    var l = velocity.dot(right);

    // 3) Motor, freio e ré.
    braking = (throttleInput < 0 && f > 5) || handbrake;
    if (throttleInput > 0) {
      f += accelerationRate * throttleInput * dt;
    } else if (throttleInput < 0) {
      f += throttleInput * (f > 0 ? brakeRate : accelerationRate * 0.6) * dt;
    }

    // Arrasto (independente do FPS) e freio de mão.
    f *= exp(-drag * dt);
    if (handbrake) f *= exp(-1.0 * dt);
    f = f.clamp(-maxSpeed / 3, maxSpeed).toDouble();

    // 4) Aderência lateral: o que sobra de velocidade lateral vira derrapagem.
    slip = l.abs();
    l *= exp(-(handbrake ? gripHandbrake : gripNormal) * dt);

    // 5) Recompõe a velocidade e move o carro.
    velocity.setValues(
      fwd.x * f + right.x * l,
      fwd.y * f + right.y * l,
    );
    position += velocity * dt;

    // 6) Guard-rails e marcas de pneu.
    _collideWithWalls(track);
    currentSpeed = velocity.length;

    if (slip > 35 && currentSpeed > 60) _addSkidMarks(track);
  }

  void _addSkidMarks(TrackComponent track) {
    final c = cos(angle);
    final s = sin(angle);
    for (final sx in const [-1.0, 1.0]) {
      final lx = sx * (size.x / 2 - 2);
      final ly = size.y / 2 - 8;
      track.addSkid(Offset(
        position.x + lx * c - ly * s,
        position.y + lx * s + ly * c,
      ));
    }
  }

  // Barreira física (guard-rail) usando a distância exata ao contorno
  // arredondado da pista, funciona igual nas retas e nas curvas.
  void _collideWithWalls(TrackComponent track) {
    final sd = track.signedDistance(position, _normal);
    final limit = track.trackWidth / 2 - 8;
    final penetration = sd.abs() - limit;
    if (penetration <= 0) return;

    // Direção que aponta para fora da área permitida
    final side = sd > 0 ? 1.0 : -1.0;
    final ox = _normal.x * side;
    final oy = _normal.y * side;

    position.x -= ox * penetration;
    position.y -= oy * penetration;

    // Componente da velocidade indo contra a parede: rebate e perde energia.
    final vn = velocity.x * ox + velocity.y * oy;
    if (vn > 0) {
      velocity.x -= ox * vn * 1.35; // ~35% de quique
      velocity.y -= oy * vn * 1.35;
      velocity.scale(0.93); // atrito ao raspar
      gameRef.onWallHit(vn); // som + vibração
    }
  }
}