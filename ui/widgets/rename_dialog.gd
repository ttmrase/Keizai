class_name RenameDialog
extends ConfirmationDialog

## Lets the player name a place or an institution.
##
## Naming goes through NamingService rather than being written here: a screen may
## ask for a change, but it does not reach into the simulation to make one.

signal name_applied(subject_id: StringName)

var _subject_id: StringName = &""
var _is_settlement := false
var _field: LineEdit


func _ready() -> void:
	ok_button_text = "改める"
	cancel_button_text = "やめる"
	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(360, 48)
	_field.max_length = SimConfig.MAX_NAME_LENGTH
	add_child(_field)
	# The dialog's own OK button is the only confirm path; submitting from the
	# keyboard should do the same thing rather than nothing.
	_field.text_submitted.connect(func(_t): _confirm())
	confirmed.connect(_confirm)


func open_for_settlement(settlement_id: StringName, current_name: String) -> void:
	_subject_id = settlement_id
	_is_settlement = true
	title = "地名を改める"
	_show(current_name)


func open_for_organization(org_id: StringName, current_name: String) -> void:
	_subject_id = org_id
	_is_settlement = false
	title = "名を改める"
	_show(current_name)


func _show(current_name: String) -> void:
	_field.text = current_name
	popup_centered()
	_field.grab_focus()
	_field.select_all()


func _confirm() -> void:
	if _subject_id == &"":
		return
	var ok := NamingService.rename_settlement(_subject_id, _field.text) if _is_settlement \
		else NamingService.rename_organization(_subject_id, _field.text)
	if ok:
		name_applied.emit(_subject_id)
	hide()
