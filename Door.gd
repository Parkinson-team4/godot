extends Area3D

@export var next_scene_path: String = "res://outs.tscn"
@export var spawn_point_name: String = "SpawnPoint"

var player_in_range = false

func _ready():
	# 플레이어가 문 근처에 왔을 때 감지
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# 디버그: Area3D 설정 확인
	print("Door Area3D 준비 완료")
	print("CollisionShape3D 개수: ", get_children().filter(func(child): return child is CollisionShape3D).size())

func _on_body_entered(body):
	print("뭔가 들어옴: ", body.name, " 타입: ", body.get_class())
	if body is CharacterBody3D:  # CharacterBody3D 타입이면 플레이어로 간주
		player_in_range = true
		show_interaction_hint()
		print("플레이어가 문 근처에 접근!")

func _on_body_exited(body):
	print("뭔가 나감: ", body.name)
	if body is CharacterBody3D:
		player_in_range = false
		hide_interaction_hint()
		print("플레이어가 문에서 멀어짐")

func _input(event):
	if player_in_range and event is InputEventKey and event.keycode == KEY_E and event.pressed:
		open_door()

func open_door():
	print("문 열기! 씬 전환...")
	# 문 열리는 애니메이션이 있다면
	# $AnimationPlayer.play("door_open")
	# await $AnimationPlayer.animation_finished
	
	change_scene()

func change_scene():
	# SceneManager를 통해 씬 전환
	SceneManager.change_scene_to(next_scene_path, spawn_point_name)

func show_interaction_hint():
	# UI 표시 로직 (나중에 구현)
	print("E키를 눌러 문 열기")

func hide_interaction_hint():
	# UI 숨기기 로직
	pass
