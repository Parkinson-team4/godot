# 자유 시점 카메라 컨트롤러
# F6 실행 중에 마우스와 키보드로 카메라 조작 가능

extends Camera3D

# 카메라 이동 설정
@export var move_speed: float = 5.0        # 이동 속도
@export var mouse_sensitivity: float = 0.1  # 마우스 감도
@export var zoom_speed: float = 2.0         # 줌 속도

# 내부 변수
var mouse_captured: bool = false
var rotation_x: float = 0.0
var rotation_y: float = 0.0

func _ready():
	print("🎥 자유 시점 카메라 활성화")
	print("조작법:")
	print("  우클릭: 마우스 캡처/해제")
	print("  WASD: 이동")
	print("  마우스: 시점 회전")
	print("  휠: 줌")
	print("  Shift: 빠른 이동")
	print("  ESC: 마우스 해제")

func _input(event):
	# 마우스 캡처 토글 (우클릭)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			toggle_mouse_capture()
	
	# ESC키로 마우스 해제
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			release_mouse()
	
	# 마우스 이동 (캡처된 상태에서만)
	if event is InputEventMouseMotion and mouse_captured:
		rotation_y -= event.relative.x * mouse_sensitivity
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -90, 90)
		
		# 회전 적용
		rotation_degrees = Vector3(rotation_x, rotation_y, 0)
	
	# 마우스 휠 줌
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_forward(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_backward(zoom_speed)

func _process(delta):
	# 키보드 이동
	var input_vector = Vector3.ZERO
	var current_speed = move_speed
	
	# Shift 키로 빠른 이동
	if Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SHIFT):
		current_speed *= 3.0
	
	# WASD 이동
	if Input.is_key_pressed(KEY_W):
		input_vector.z -= 1
	if Input.is_key_pressed(KEY_S):
		input_vector.z += 1
	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_key_pressed(KEY_Q):
		input_vector.y -= 1
	if Input.is_key_pressed(KEY_E):
		input_vector.y += 1
	
	# 이동 적용
	if input_vector != Vector3.ZERO:
		# 카메라 방향 기준으로 이동
		var movement = transform.basis * input_vector * current_speed * delta
		global_position += movement

func toggle_mouse_capture():
	"""마우스 캡처 토글"""
	if mouse_captured:
		release_mouse()
	else:
		capture_mouse()

func capture_mouse():
	"""마우스 캡처"""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true
	print("🖱️ 마우스 캡처됨 - 시점 회전 가능")

func release_mouse():
	"""마우스 해제"""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false
	print("🖱️ 마우스 해제됨")

func move_forward(distance: float):
	"""앞으로 이동"""
	global_position -= transform.basis.z * distance

func move_backward(distance: float):
	"""뒤로 이동"""
	global_position += transform.basis.z * distance

func _exit_tree():
	"""씬 종료 시 마우스 해제"""
	release_mouse()
