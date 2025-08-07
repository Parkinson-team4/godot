extends Node

var current_scene = null

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	print("SceneManager 준비 완료")

func change_scene_to(path: String, spawn_point_name: String = ""):
	print("씬 전환 시작: ", path)
	call_deferred("_deferred_change_scene", path, spawn_point_name)

func _deferred_change_scene(path: String, spawn_point_name: String):
	# 씬 파일 존재 확인
	if not ResourceLoader.exists(path):
		push_error("씬 파일을 찾을 수 없습니다: " + path)
		return
	
	# 현재 씬 해제
	current_scene.free()
	
	# 새 씬 로드
	var new_scene_resource = ResourceLoader.load(path)
	if new_scene_resource == null:
		push_error("씬 로드 실패: " + path)
		return
	
	current_scene = new_scene_resource.instantiate()
	if current_scene == null:
		push_error("씬 인스턴스 생성 실패: " + path)
		return
		
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	
	print("새 씬 로드 완료: ", path)
	
	# 플레이어 위치 설정
	if spawn_point_name != "":
		await get_tree().process_frame  # 씬 완전 로드 대기
		position_player_at_spawn_point(spawn_point_name)

func position_player_at_spawn_point(spawn_point_name: String):
	var spawn_point = current_scene.get_node_or_null(spawn_point_name)
	var player = current_scene.get_node_or_null("Player")
	
	if spawn_point and player:
		player.global_position = spawn_point.global_position
		print("플레이어 위치 설정: ", spawn_point.global_position)
	else:
		if not spawn_point:
			print("스폰포인트를 찾을 수 없음: ", spawn_point_name)
		if not player:
			print("플레이어를 찾을 수 없음")
