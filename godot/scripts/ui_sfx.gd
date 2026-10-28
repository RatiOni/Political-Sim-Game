extends Node

const MIX_RATE := 22050
const VOICE_COUNT := 4
const VOLUME_DB := -20.0

var enabled := true
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _index in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		player.volume_db = VOLUME_DB
		add_child(player)
		_voices.append(player)


func _exit_tree() -> void:
	for player in _voices:
		player.stop()
		player.stream = null
	_voices.clear()

func navigation() -> void:
	_play(PackedFloat32Array([420.0, 630.0]), 0.055, 0.19, 34.0)


func selection() -> void:
	_play(PackedFloat32Array([610.0, 915.0]), 0.065, 0.16, 22.0)


func confirm() -> void:
	_play(PackedFloat32Array([330.0, 495.0, 660.0]), 0.14, 0.16, 18.0)


func deny() -> void:
	_play(PackedFloat32Array([340.0, 255.0]), 0.11, 0.14, -46.0)


func clock_tick() -> void:
	_play(PackedFloat32Array([790.0]), 0.03, 0.10, -12.0)


func month_rollover() -> void:
	_play(PackedFloat32Array([262.0, 392.0]), 0.17, 0.15, 12.0)


func alert() -> void:
	_play(PackedFloat32Array([523.0, 784.0, 523.0, 784.0]), 0.20, 0.17, 8.0)


func _play(notes: PackedFloat32Array, duration: float, gain: float, sweep: float) -> void:
	if not enabled or notes.is_empty() or _voices.is_empty():
		return
	var stream := _make_stream(notes, duration, gain, sweep)
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = stream
	player.play()


func _make_stream(notes: PackedFloat32Array, duration: float, gain: float, sweep: float) -> AudioStreamWAV:
	var sample_count := maxi(1, ceili(duration * MIX_RATE))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in range(sample_count):
		var progress := float(index) / float(sample_count)
		var time := float(index) / float(MIX_RATE)
		var waveform := 0.0
		for note in notes:
			var frequency := note + sweep * progress
			waveform += sin(TAU * frequency * time)
		waveform /= float(notes.size())
		var attack := minf(1.0, progress * 14.0)
		var release := minf(1.0, (1.0 - progress) * 7.0)
		var sample := int(roundi(clampf(waveform * gain * attack * release, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	return stream