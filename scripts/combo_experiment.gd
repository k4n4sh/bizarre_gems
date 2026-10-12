extends RefCounted
## Local Classic experiment controls. Never persisted in player settings.
## The write lock stays on until process exit, including after returning to the menu.
static var _initialized := false
static var read_only := false
static var variant := ""
static var board_seed := 42
static var special_rules := "timed"
static var fixed_layout := false
const REPORT_PATH := "user://debug/classic_combo_ab.jsonl"


static func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if not OS.is_debug_build():
		return
	var requested := ""
	var requested_special := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--combo-ab="):
			requested = arg.get_slice("=", 1).to_upper()
		elif arg.begins_with("--special-combo="):
			requested_special = arg.get_slice("=", 1)
		elif arg.begins_with("--combo-seed="):
			var value := arg.get_slice("=", 1)
			if value.is_valid_int():
				board_seed = int(value)
	if requested in ["A", "B"]:
		select(requested, board_seed)
	if requested_special in ["legacy", "timed"]:
		select_special(requested_special, board_seed)
		if requested in ["A", "B"]:
			variant = requested


static func is_read_only() -> bool:
	initialize()
	return read_only


static func select(value: String, fixed_seed: int) -> bool:
	if not OS.is_debug_build() or value not in ["A", "B"]:
		return false
	_initialized = true
	variant = value
	special_rules = "legacy"
	fixed_layout = true
	board_seed = fixed_seed
	read_only = true
	return true


## Ordinary Classic uses the current rules and saves normally.
## Only explicit debug selections enable the process-wide experimental write lock.
static func begin_classic() -> void:
	initialize()


static func select_special(value: String, fixed_seed: int) -> bool:
	if not OS.is_debug_build() or value not in ["legacy", "timed"]:
		return false
	select("B", fixed_seed)
	special_rules = value
	return true


static func window_seconds() -> float:
	return ScoreKeeper.COMBO_WINDOW if variant == "A" else ScoreKeeper.CLASSIC_COMBO_WINDOW


static func append_report(report: Dictionary) -> void:
	if not is_read_only():
		return
	var line := JSON.stringify(report)
	print("[combo-ab] ", line)
	var directory := ProjectSettings.globalize_path("user://debug")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_warning("Combo A/B: cannot create report directory; report is in Output.")
		return
	var file := FileAccess.open(REPORT_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(REPORT_PATH) else FileAccess.WRITE)
	if file == null:
		push_warning("Combo A/B: cannot open report file; report is in Output.")
		return
	file.seek_end()
	file.store_line(line)
	file.close()
