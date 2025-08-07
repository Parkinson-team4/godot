# 1인칭 플레이어 컨트롤러
# 집 안을 돌아다니며 IoT 전등을 제어할 수 있는 플레이어

extends CharacterBody3D
class_name FirstPersonPlayer

# 이동 설정
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# 카메라 설정
@export var camera_smooth: float = 10.0
@export var head_bob_enabled: bool = true
@export var head_bob_amplitude: float = 0.05
@export var head_bob_frequency: float = 2.0

# 전등 상호작용 설정
@export var interaction_range: float = 3.0  # 전등과 상호작용할 수 있는 거리

# 노드 참조
@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interaction_raycast: RayCast3D = $Head/Camera3D/InteractionRaycast
@onready var ui_label: Label = $UI/InteractionLabel

# 내부 변수
var mouse_captured: bool = false
var camera_rotation_x: float = 0.0
var head_bob_time: float = 0.0
var current_smart_light: SmartLight = null
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	setup_player()
	setup_ui()
	capture_mouse()
	
	print("🚶 1인칭 플레이어 활성화")
	print("조작법:")
	print("  WASD: 이동")
	print("  마우스: 시점 회전")
	print("  Shift: 달리기")
	print("  Space: 점프")
	print("  E: 전등 상호작용")
	print("  ESC: 마우스 해제")
	print("  Tab: UI 토글")

func setup_player():
	"""플레이어 초기 설정"""
	# 충돌 모양 설정 (캡슐)
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision_shape.shape = capsule
	
	# 상호작용 레이캐스트 설정
	if not interaction_raycast:
		interaction_raycast = RayCast3D.new()
		camera.add_child(interaction_raycast)
	
	interaction_raycast.target_position = Vector3(0, 0, -interaction_range)
	interaction_raycast.enabled = true
	interaction_raycast.collision_mask = 1  # 기본 레이어

func setup_ui():
	"""UI 설정"""
	if not ui_label:
		# UI 노드 생성
		var ui_container = Control.new()
		ui_container.name = "UI"
		ui_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(ui_container)
		
		ui_label = Label.new()
		ui_label.name = "InteractionLabel"
		ui_label.text = ""
		ui_label.position = Vector2(50, 50)
		ui_label.add_theme_font_size_override("font_size", 24)
		ui_label.add_theme_color_override("font_color", Color.WHITE)
		ui_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		ui_label.add_theme_constant_override("shadow_offset_x", 2)
		ui_label.add_theme_constant_override("shadow_offset_y", 2)
		ui_container.add_child(ui_label)
		
		# 크로스헤어 추가
		var crosshair = Label.new()
		crosshair.name = "Crosshair"
		crosshair.text = "+"
		crosshair.add_theme_font_size_override("font_size", 32)
		crosshair.add_theme_color_override("font_color", Color.WHITE)
		crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ui_container.add_child(crosshair)

func _input(event):
	# 마우스 시점 회전
	if event is InputEventMouseMotion and mouse_captured:
		# 좌우 회전 (Y축)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# 상하 회전 (X축) - 제한
		camera_rotation_x -= event.relative.y * mouse_sensitivity
		camera_rotation_x = clamp(camera_rotation_x, -1.5, 1.2)  # 약 -85도 ~ +70도
		head.rotation.x = camera_rotation_x
	
	# 키보드 입력
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				toggle_mouse_capture()
			KEY_E:
				interact_with_light()
			KEY_TAB:
				toggle_ui()

func _physics_process(delta):
	# 중력 적용
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# 점프
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
	
	# 이동 처리
	handle_movement(delta)
	
	# 물리 이동 적용
	move_and_slide()
	
	# 헤드 밥 효과
	if head_bob_enabled:
		apply_head_bob(delta)
	
	# 전등 상호작용 체크
	check_light_interaction()

func handle_movement(delta):
	"""이동 처리"""
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# WASD 키보드 입력 대체
	if Input.is_key_pressed(KEY_W):
		input_dir.y = -1
	elif Input.is_key_pressed(KEY_S):
		input_dir.y = 1
	else:
		input_dir.y = 0
		
	if Input.is_key_pressed(KEY_A):
		input_dir.x = -1
	elif Input.is_key_pressed(KEY_D):
		input_dir.x = 1
	else:
		input_dir.x = 0
	
	# 속도 결정 (달리기/걷기)
	var speed = run_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	
	# 방향 계산 (플레이어 기준)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * delta * 3)
		velocity.z = move_toward(velocity.z, 0, speed * delta * 3)

func apply_head_bob(delta):
	"""헤드 밥 효과"""
	if velocity.length() > 0.1 and is_on_floor():
		head_bob_time += delta * velocity.length() * head_bob_frequency
		var bob_offset = sin(head_bob_time) * head_bob_amplitude
		camera.position.y = lerp(camera.position.y, 0.0 + bob_offset, delta * camera_smooth)
	else:
		camera.position.y = lerp(camera.position.y, 0.0, delta * camera_smooth)

func check_light_interaction():
	"""전등과의 상호작용 체크"""
	if interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		
		# SmartLight 찾기 (충돌 대상이나 그 부모에서)
		var smart_light = find_smart_light_in_node(collider)
		
		if smart_light and smart_light != current_smart_light:
			current_smart_light = smart_light
			update_interaction_ui(smart_light)
		elif not smart_light and current_smart_light:
			current_smart_light = null
			clear_interaction_ui()
	else:
		if current_smart_light:
			current_smart_light = null
			clear_interaction_ui()

func find_smart_light_in_node(node: Node) -> SmartLight:
	"""노드에서 SmartLight 찾기"""
	# 현재 노드가 SmartLight인지 확인
	if node is SmartLight:
		return node
	
	# 부모 노드들을 확인
	var parent = node.get_parent()
	while parent:
		if parent is SmartLight:
			return parent
		parent = parent.get_parent()
	
	return null

func update_interaction_ui(smart_light: SmartLight):
	"""상호작용 UI 업데이트"""
	var status = "켜짐" if smart_light.is_light_on else "꺼짐"
	var brightness = int(smart_light.brightness * 100)
	
	ui_label.text = """[E] %s
상태: %s | 밝기: %d%%
온도: %.1f°C""" % [
		smart_light.device_id,
		status,
		brightness,
		smart_light.temperature
	]
	ui_label.visible = true

func clear_interaction_ui():
	"""상호작용 UI 지우기"""
	ui_label.text = ""
	ui_label.visible = false

func interact_with_light():
	"""전등과 상호작용"""
	if current_smart_light:
		current_smart_light.toggle_light()
		update_interaction_ui(current_smart_light)
		print("🔌 %s 전등 조작됨" % current_smart_light.device_id)

func capture_mouse():
	"""마우스 캡처"""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true
	print("🖱️ 마우스 캡처됨")

func release_mouse():
	"""마우스 해제"""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false
	print("🖱️ 마우스 해제됨")

func toggle_mouse_capture():
	"""마우스 캡처 토글"""
	if mouse_captured:
		release_mouse()
	else:
		capture_mouse()

func toggle_ui():
	"""UI 토글"""
	var ui = get_node_or_null("UI")
	if ui:
		ui.visible = !ui.visible

# =============================================================================
# 전등 제어 단축키 (플레이어가 바라보는 전등 제어)
# =============================================================================

func _unhandled_key_input(event):
	"""전등 제어 단축키"""
	if not event.pressed or not current_smart_light:
		return
	
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			# 숫자키로 밝기 조절
			var brightness_levels = [0.2, 0.4, 0.6, 0.8, 1.0]
			var index = event.keycode - KEY_1
			if index < brightness_levels.size():
				current_smart_light.set_brightness(brightness_levels[index])
				print("💡 밝기 %d%% 설정" % (brightness_levels[index] * 100))
		
		KEY_R:
			current_smart_light.set_color(Color.RED)
			print("🔴 빨간색으로 변경")
		KEY_G:
			current_smart_light.set_color(Color.GREEN)
			print("🟢 녹색으로 변경")
		KEY_B:
			current_smart_light.set_color(Color.BLUE)
			print("🔵 파란색으로 변경")
		KEY_Y:
			current_smart_light.set_color(Color.YELLOW)
			print("🟡 노란색으로 변경")
		KEY_W:
			current_smart_light.set_color(Color.WHITE)
			print("⚪ 흰색으로 변경")

func _exit_tree():
	"""씬 종료 시 정리"""
	release_mouse()
