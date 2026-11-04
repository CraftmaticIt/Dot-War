extends Node
## Autoload "Sfx": neon-synth sound effects generated in code (no audio files) + sound settings.
## Every Button in the game clicks automatically; other sounds via Sfx.play("name").

const RATE := 22050
const SETTINGS_PATH := "user://settings.cfg"
const MIN_GAP := 0.06  # same sound retriggers at most this often (tower hits come in bursts)

var enabled := true
var volume := 0.8  # 0..1
var sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _last := {}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value("sound", "enabled", true))
		volume = clampf(float(cfg.get_value("sound", "volume", 0.8)), 0.0, 1.0)
	sounds = {
		"click": tone(900, 650, 0.04, "square", 0.25),
		"build": tone(420, 840, 0.14, "sine", 0.5) + tone(840, 1260, 0.1, "sine", 0.35),
		"error": tone(220, 180, 0.14, "square", 0.3),
		"send": tone(260, 980, 0.18, "saw", 0.3, 0.25),
		"hit": tone(160, 60, 0.07, "noise", 0.35),
		"capture": tone(660, 990, 0.09, "sine", 0.45),
		"boost": tone(300, 1500, 0.25, "square", 0.25),
		"win": tone(523, 523, 0.12, "sine", 0.5) + tone(659, 659, 0.12, "sine", 0.5) + tone(784, 1046, 0.3, "sine", 0.5),
		"lose": tone(392, 330, 0.2, "saw", 0.35) + tone(330, 150, 0.45, "saw", 0.35),
	}
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(func(n: Node):
		if n is BaseButton:
			n.pressed.connect(play.bind("click")))

## 16-bit mono PCM: frequency sweep f0->f1, short attack, exponential decay.
static func tone(f0: float, f1: float, secs: float, wave: String, amp: float, noise := 0.0) -> PackedByteArray:
	var n := int(RATE * secs)
	var out := PackedByteArray()
	out.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var x := phase - floorf(phase)
		var s: float
		match wave:
			"square":
				s = 1.0 if x < 0.5 else -1.0
			"saw":
				s = 2.0 * x - 1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0) * 0.7 + sin(TAU * phase) * 0.3
			_:
				s = sin(TAU * x)
		if noise > 0.0:
			s = lerpf(s, rng.randf_range(-1.0, 1.0), noise)
		var env := minf(1.0, i / (RATE * 0.004)) * exp(-4.0 * t)
		out.encode_s16(i * 2, int(clampf(s * env * amp, -1.0, 1.0) * 32767.0))
	return out

func play(name: String) -> void:
	if not enabled or volume <= 0.0 or not sounds.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < MIN_GAP:
		return
	_last[name] = now
	for p in _players:
		if not p.playing:
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = RATE
			w.data = sounds[name]
			p.stream = w
			p.volume_db = linear_to_db(volume)
			p.play()
			return

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "enabled", enabled)
	cfg.set_value("sound", "volume", volume)
	cfg.save(SETTINGS_PATH)
